import json
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import stripe
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .auth import current_user
from .config import settings
from .database import get_db
from .models import (BillingCustomer, Booking, MusicianBusyDate, MusicianPayoutDestination,
                     MusicianProfile, StripeWebhookEvent, User, UserRole)
from .notifications import enqueue

router = APIRouter(prefix="/api/billing", tags=["billing"])


class CheckoutRequest(BaseModel):
    booking_id: int


def connect_return_page(*, complete: bool) -> HTMLResponse:
    title = "Cuenta enviada a revisión" if complete else "Continúa configurando tu cuenta"
    message = (
        "Stripe recibió tus datos. Balam actualizará el estado automáticamente."
        if complete else
        "El enlace venció o faltan datos. Vuelve a Balam para generar uno nuevo."
    )
    destination = "balam://connect/return" if complete else "balam://connect/refresh"
    return HTMLResponse(f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>
body{{margin:0;background:#180d31;color:#fff;font-family:Arial,sans-serif;display:grid;place-items:center;min-height:100vh;text-align:center}}
main{{padding:32px;max-width:460px}}h1{{font-size:30px}}p{{color:#d8cfeb;font-size:18px;line-height:1.5}}
a{{display:block;margin-top:28px;padding:17px 24px;border-radius:30px;background:#cbb6ff;color:#251541;text-decoration:none;font-weight:700}}
</style></head><body><main><h1>{title}</h1><p>{message}</p><a href="{destination}">Volver a Balam</a></main>
<script>setTimeout(function(){{location.href='{destination}'}},700)</script></body></html>""")


@router.get("/connect/return", response_class=HTMLResponse)
def connect_return():
    return connect_return_page(complete=True)


@router.get("/connect/refresh", response_class=HTMLResponse)
def connect_refresh():
    return connect_return_page(complete=False)


def checkout_return_page(*, validating: bool) -> HTMLResponse:
    if validating:
        title = "Estamos validando tu pago"
        message = (
            "Esta fecha ya está apartada por usted. Favor de verificar unos "
            "minutos más para confirmar que la contratación es efectiva."
        )
        destination = "balam://billing/success"
    else:
        title = "Pago cancelado"
        message = "No se realizó ningún cargo. Puedes volver a Balam e intentarlo otra vez."
        destination = "balam://billing/cancel"
    return HTMLResponse(f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>
body{{margin:0;background:#180d31;color:#fff;font-family:Arial,sans-serif;display:grid;place-items:center;min-height:100vh;text-align:center}}
main{{padding:32px;max-width:460px}}h1{{font-size:32px}}p{{color:#d8cfeb;font-size:18px;line-height:1.5}}
a{{display:block;margin-top:28px;padding:17px 24px;border-radius:30px;background:#cbb6ff;color:#251541;text-decoration:none;font-weight:700}}
</style></head><body><main><h1>{title}</h1><p>{message}</p><a href="{destination}">Volver a Balam</a></main>
<script>setTimeout(function(){{location.href='{destination}'}},500)</script></body></html>""")


@router.get("/checkout/success", response_class=HTMLResponse)
def checkout_success(session_id: str | None = None, db: Session = Depends(get_db)):
    # The local Stripe CLI webhook may not be running during emulator tests.
    # Confirm the session directly with Stripe so the booking is still marked
    # paid when Checkout redirects the browser back to this endpoint.
    if session_id:
        try:
            stripe_client_ready()
            session = stripe.checkout.Session.retrieve(session_id)
            sync_checkout("checkout.session.completed", session, db)
            db.commit()
        except stripe.error.StripeError:
            db.rollback()
    return checkout_return_page(validating=True)


@router.get("/checkout/cancel", response_class=HTMLResponse)
def checkout_cancel():
    return checkout_return_page(validating=False)


def stripe_client_ready() -> None:
    if not settings.stripe_secret_key:
        raise HTTPException(503, "Stripe Billing no está configurado")
    stripe.api_key = settings.stripe_secret_key


def stripe_object_dict(value) -> dict:
    if hasattr(value, "to_dict_recursive"):
        return value.to_dict_recursive()
    if hasattr(value, "to_dict"):
        return value.to_dict()
    return dict(value)


def sync_connect_account(account, db: Session) -> MusicianPayoutDestination | None:
    data = stripe_object_dict(account)
    account_id = data.get("id")
    metadata = data.get("metadata") or {}
    raw_musician_id = metadata.get("balam_musician_id")
    destination = None
    if account_id:
        destination = db.scalar(select(MusicianPayoutDestination).where(
            MusicianPayoutDestination.stripe_connected_account_id == account_id
        ))
    if destination is None and raw_musician_id and str(raw_musician_id).isdigit():
        destination = db.scalar(select(MusicianPayoutDestination).where(
            MusicianPayoutDestination.musician_id == int(raw_musician_id)
        ))
    if destination is None:
        return None
    requirements = data.get("requirements") or {}
    due = sorted(set(
        (requirements.get("currently_due") or [])
        + (requirements.get("past_due") or [])
    ))
    destination.stripe_details_submitted = bool(data.get("details_submitted"))
    destination.stripe_payouts_enabled = bool(data.get("payouts_enabled"))
    destination.stripe_requirements_due = json.dumps(due, separators=(",", ":"))
    return destination


@router.post("/connect/onboarding", status_code=201)
def create_connect_onboarding(
    user: User = Depends(current_user), db: Session = Depends(get_db),
):
    if user.role != UserRole.musician:
        raise HTTPException(403, "Sólo las agrupaciones pueden configurar depósitos")
    profile = db.scalar(select(MusicianProfile).where(MusicianProfile.user_id == user.id))
    if not profile:
        raise HTTPException(409, "Crea primero el perfil de la agrupación")
    stripe_client_ready()
    destination = db.scalar(select(MusicianPayoutDestination).where(
        MusicianPayoutDestination.musician_id == profile.id
    ))
    if destination is None:
        destination = MusicianPayoutDestination(musician_id=profile.id)
        db.add(destination)
        db.flush()
    try:
        if not destination.stripe_connected_account_id:
            account = stripe.Account.create(
                type="standard",
                country="MX",
                email=user.email,
                capabilities={"transfers": {"requested": True}},
                metadata={
                    "balam_musician_id": str(profile.id),
                    "balam_user_id": str(user.id),
                },
                idempotency_key=f"balam-musician-{profile.id}-connect-standard-v1",
            )
            destination.stripe_connected_account_id = account.id
            sync_connect_account(account, db)
            db.commit()
        else:
            account = stripe.Account.retrieve(destination.stripe_connected_account_id)
            account_data = stripe_object_dict(account)
            metadata = account_data.get("metadata") or {}
            if metadata.get("balam_musician_id") != str(profile.id):
                raise HTTPException(
                    409,
                    "La cuenta Stripe vinculada no pertenece a esta agrupación",
                )
            sync_connect_account(account, db)
            db.commit()
        link = stripe.AccountLink.create(
            account=destination.stripe_connected_account_id,
            refresh_url=settings.connect_refresh_url,
            return_url=settings.connect_return_url,
            type="account_onboarding",
            collect="eventually_due",
        )
    except stripe.error.StripeError as exc:
        db.rollback()
        detail = (
            "Activa Stripe Connect en el Dashboard de Stripe antes de "
            "registrar cuentas bancarias de agrupaciones."
            if "signed up for Connect" in str(exc)
            else "No fue posible comunicarse con Stripe. Intenta nuevamente en unos momentos."
        )
        raise HTTPException(
            502,
            detail,
        ) from exc
    return {"url": link.url, "expires_at": getattr(link, "expires_at", None)}


def customer_for(user: User, db: Session) -> BillingCustomer:
    record = db.scalar(select(BillingCustomer).where(BillingCustomer.user_id == user.id))
    if record:
        return record
    created = stripe.Customer.create(
        email=user.email,
        metadata={"balam_user_id": str(user.id)},
    )
    record = BillingCustomer(user_id=user.id, stripe_customer_id=created.id)
    db.add(record)
    db.commit()
    db.refresh(record)
    return record


@router.post("/checkout-sessions", status_code=201)
def create_checkout_session(
    data: CheckoutRequest,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    booking = db.get(Booking, data.booking_id)
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if booking.client.user_id != user.id:
        raise HTTPException(403, "Esta contratación pertenece a otro cliente")
    if booking.payment_status == "paid":
        raise HTTPException(409, "Esta contratación ya está pagada")
    if booking.payment_status in {"refunded", "refund_pending", "refund_failed"}:
        raise HTTPException(409, "Este pago tiene un reembolso por conflicto de fecha")

    stripe_client_ready()

    # Serialize checkout creation for this group.  The partial unique index is
    # the durable second line of defence when multiple API replicas receive
    # requests at exactly the same time.
    db.scalar(
        select(MusicianProfile)
        .where(MusicianProfile.id == booking.musician_id)
        .with_for_update()
    )
    if db.scalar(select(MusicianBusyDate.id).where(
        MusicianBusyDate.musician_id == booking.musician_id,
        MusicianBusyDate.busy_date == booking.event_date,
    )):
        raise HTTPException(409, "La fecha ya no está disponible; no se iniciará otro pago")
    reserved_booking = db.scalar(
        select(Booking.id).where(
            Booking.musician_id == booking.musician_id,
            Booking.event_date == booking.event_date,
            Booking.booking_type == "surprise",
            Booking.payment_status.in_(("checkout_created", "validating_payment", "paid")),
            Booking.id != booking.id,
        )
    )
    if reserved_booking:
        raise HTTPException(
            409,
            "La fecha está apartada temporalmente mientras se valida otro pago",
        )
    if booking.total_cents <= 0:
        raise HTTPException(409, "La contratación no tiene un total válido")
    if booking.stripe_checkout_session_id:
        try:
            previous = stripe.checkout.Session.retrieve(
                booking.stripe_checkout_session_id
            )
            if previous.payment_status in {"paid", "no_payment_required"}:
                sync_checkout("checkout.session.completed", previous, db)
                db.commit()
                raise HTTPException(409, "Esta contratación ya está pagada")
            if previous.status == "open" and previous.url:
                return_path = "/api/billing/checkout/success"
                if return_path in (previous.success_url or ""):
                    return {"id": previous.id, "url": previous.url}
                # Sessions created by older builds returned to localhost:3000.
                # Expire them so this attempt receives the corrected return URL.
                stripe.checkout.Session.expire(previous.id)
        except stripe.error.StripeError:
            pass

    # Persist the reservation before calling Stripe.  Without this commit a
    # second request handled by another API instance could create a second
    # checkout for the same surprise group and date.
    if booking.booking_type == "surprise":
        booking.payment_status = "checkout_created"
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(
                409,
                "Otro cliente acaba de apartar este Grupo Sorpresa para esa fecha",
            )

    customer = customer_for(user, db)
    try:
        session = stripe.checkout.Session.create(
            mode="payment",
            customer=customer.stripe_customer_id,
            line_items=[{
            "price_data": {
                "currency": booking.currency,
                "unit_amount": booking.total_cents,
                "product_data": {
                    "name": (
                        "Grupo Sorpresa Garibaldy"
                        if booking.booking_type == "surprise"
                        else f"Contratación de {booking.musician.group_name}"
                    ),
                    "description": (
                        f"{booking.duration_minutes / 60:g} horas · "
                        f"evento {booking.event_date.isoformat()}"
                    ),
                },
            },
            "quantity": 1,
        }],
        success_url=settings.billing_success_url,
        cancel_url=settings.billing_cancel_url,
        client_reference_id=str(booking.id),
        metadata={"balam_user_id": str(user.id), "booking_id": str(booking.id)},
            payment_intent_data={
                "metadata": {"balam_user_id": str(user.id), "booking_id": str(booking.id)},
                "transfer_group": f"balam_booking_{booking.id}",
            },
            invoice_creation={"enabled": True},
            billing_address_collection="required",
            # A surprise group is inventory: it must return to the matching
            # pool promptly when the client leaves Checkout without paying.
            # Stripe accepts 30 minutes as its minimum session duration.
            **({
                "expires_at": int((datetime.now(timezone.utc) + timedelta(minutes=30)).timestamp()),
            } if booking.booking_type == "surprise" else {}),
        )
    except stripe.error.StripeError:
        if booking.booking_type == "surprise" and not booking.stripe_checkout_session_id:
            booking.payment_status = "pending"
            db.commit()
        raise
    booking.stripe_checkout_session_id = session.id
    booking.payment_status = "checkout_created"
    db.commit()
    return {"id": session.id, "url": session.url}


@router.get("/invoices")
def list_invoices(user: User = Depends(current_user), db: Session = Depends(get_db)):
    stripe_client_ready()
    customer = db.scalar(select(BillingCustomer).where(BillingCustomer.user_id == user.id))
    if not customer:
        return []
    invoices = stripe.Invoice.list(customer=customer.stripe_customer_id, limit=25)
    return [{
        "id": item.id,
        "number": item.number,
        "status": item.status,
        "currency": item.currency,
        "amount_due": item.amount_due,
        "amount_paid": item.amount_paid,
        "hosted_invoice_url": item.hosted_invoice_url,
        "invoice_pdf": item.invoice_pdf,
        "created": item.created,
    } for item in invoices.auto_paging_iter()]


@router.get("/bookings/{booking_id}/status")
def payment_status(
    booking_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    booking = db.get(Booking, booking_id)
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if booking.client.user_id != user.id and booking.musician.user_id != user.id:
        raise HTTPException(403, "Esta contratación pertenece a otro usuario")
    return {"booking_id": booking.id, "payment_status": booking.payment_status}


def sync_checkout(event_type: str, obj, db: Session) -> None:
    if hasattr(obj, "to_dict"):
        obj = obj.to_dict()
    raw_booking_id = obj.get("metadata", {}).get("booking_id")
    if not raw_booking_id or not raw_booking_id.isdigit():
        return
    booking = db.get(Booking, int(raw_booking_id))
    if not booking:
        return
    db.scalar(select(MusicianProfile).where(
        MusicianProfile.id == booking.musician_id,
    ).with_for_update())
    db.refresh(booking)
    session_id = obj.get("id")
    if not session_id or booking.stripe_checkout_session_id != session_id:
        return
    if event_type in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        if obj.get("payment_status") in {"paid", "no_payment_required"}:
            # Serialize both payment confirmations and manual calendar changes.
            # Lock the parent even when no busy-date row exists yet.
            if booking.payment_status in {"paid", "refunded", "refund_pending", "refund_failed"}:
                return
            busy = db.scalar(select(MusicianBusyDate).where(
                MusicianBusyDate.musician_id == booking.musician_id,
                MusicianBusyDate.busy_date == booking.event_date,
            ))
            booking.stripe_payment_intent_id = obj.get("payment_intent")
            if busy:
                # Two customers can pay previously opened Checkout pages. Only
                # the first confirmed payment wins; refund the other in full.
                # On transport failure the transaction rolls back and Stripe
                # retries the webhook with the same refund idempotency key.
                if not booking.stripe_payment_intent_id:
                    raise HTTPException(409, "El pago en conflicto no tiene PaymentIntent")
                stripe_client_ready()
                refund = stripe.Refund.create(
                    payment_intent=booking.stripe_payment_intent_id,
                    metadata={"booking_id": str(booking.id), "reason": "date_unavailable"},
                    idempotency_key=f"balam-booking-{booking.id}-date-conflict-refund-v1",
                )
                status = getattr(refund, "status", "pending")
                booking.payment_status = (
                    "refunded" if status == "succeeded" else
                    "refund_failed" if status in {"failed", "canceled"} else "refund_pending"
                )
                booking.payout_status = "date_conflict"
                booking.payout_error = "La fecha ya estaba ocupada al confirmar Stripe el pago"
                enqueue(db, user_id=booking.client.user_id,
                        event_key=f"booking_date_conflict:{booking.id}", kind="payment",
                        title="La fecha ya no está disponible",
                        body="Otro compromiso se confirmó antes. Tu contratación no fue confirmada; revisa el estado del reembolso con la administración.",
                        data={"booking_id": str(booking.id)})
                for admin in db.scalars(select(User).where(
                    User.role == UserRole.admin, User.is_active.is_(True),
                )):
                    enqueue(db, user_id=admin.id,
                            event_key=f"booking_date_conflict:{booking.id}", kind="payment",
                            title="Reembolso por conflicto de fecha",
                            body=f"Contratación #{booking.id}: {booking.payment_status}. La fecha no se confirmó; revisa el reembolso en Stripe.",
                            data={"booking_id": str(booking.id)})
                return
            db.add(MusicianBusyDate(
                musician_id=booking.musician_id, busy_date=booking.event_date,
            ))
            first_confirmation = booking.payment_status != "paid"
            booking.payment_status = "paid"
            booking.payment_validation_started_at = None
            if booking.booking_type == "surprise" and booking.surprise_revealed_at is None:
                booking.surprise_revealed_at = datetime.now(
                    timezone.utc
                ).replace(tzinfo=None)
            if booking.payout_status == "awaiting_payment":
                booking.payout_status = "musician_funds_held"
            booking.stripe_payment_intent_id = obj.get("payment_intent")
            if first_confirmation:
                if booking.booking_type == "surprise":
                    enqueue(db, user_id=booking.client.user_id,
                            event_key=f"surprise_revealed:{booking.id}", kind="booking",
                            title="¡Tu Grupo Sorpresa está listo!",
                            body=f"Tu agrupación es {booking.musician.group_name}. Ya puedes consultar el contrato.",
                            data={"booking_id": str(booking.id)})
                enqueue(db, user_id=booking.client.user_id,
                        event_key=f"booking_paid_client:{booking.id}", kind="payment",
                        title="Pago confirmado",
                        body="Stripe confirmó tu pago y la fecha de tu evento quedó apartada.",
                        data={"booking_id": str(booking.id)})
                enqueue(db, user_id=booking.musician.user_id,
                        event_key=f"booking_paid:{booking.id}", kind="booking",
                        title="Contratación confirmada",
                        body="El cliente confirmó y pagó la contratación.",
                        data={"booking_id": str(booking.id)})
                # El contrato se congela al crear la contratación y sólo se
                # vuelve efectivo después de la confirmación de Stripe. Ambos
                # participantes reciben un aviso independiente del pago para
                # que puedan abrirlo desde su sección de contratos.
                for recipient_id in (booking.client.user_id, booking.musician.user_id):
                    enqueue(db, user_id=recipient_id,
                            event_key=f"booking_contract_ready:{booking.id}", kind="booking",
                            title="Contrato disponible",
                            body="Tu contrato confirmado ya está disponible en Mis contratos.",
                            data={"booking_id": str(booking.id)})
        elif event_type == "checkout.session.completed" and booking.payment_status not in {
            "paid", "refunded", "refund_pending", "refund_failed",
        }:
            # El cliente terminó Checkout, pero Stripe todavía no confirma el
            # cobro (por ejemplo, métodos de pago asíncronos). No se agrega la
            # fecha al calendario hasta recibir la confirmación definitiva.
            booking.payment_status = "validating_payment"
            booking.payment_validation_started_at = datetime.now(
                timezone.utc
            ).replace(tzinfo=None)
    elif event_type == "checkout.session.async_payment_failed" and booking.payment_status not in {"paid", "refunded", "refund_pending", "refund_failed"}:
        booking.payment_status = "failed"
        booking.payment_validation_started_at = None
        enqueue(db, user_id=booking.client.user_id,
                event_key=f"booking_payment_failed:{booking.id}", kind="payment",
                title="No se confirmó el pago",
                body="Stripe no pudo confirmar tu pago. Puedes intentar contratar nuevamente.",
                data={"booking_id": str(booking.id)})
    elif event_type == "checkout.session.expired" and booking.payment_status not in {"paid", "refunded", "refund_pending", "refund_failed"}:
        booking.payment_status = "expired"
        booking.payment_validation_started_at = None
        enqueue(db, user_id=booking.client.user_id,
                event_key=f"booking_checkout_expired:{booking.id}", kind="payment",
                title="Venció el tiempo para pagar",
                body="La sesión de pago expiró. Puedes iniciar una nueva contratación si la fecha sigue disponible.",
                data={"booking_id": str(booking.id)})


def release_musician_funds(booking_id: int, db: Session) -> bool:
    """Transfer an approved booking exactly once to its connected account."""
    booking = db.get(Booking, booking_id)
    if not booking or booking.payout_status != "approved_for_payout":
        return False
    if booking.stripe_transfer_id:
        booking.payout_status = "transferred"
        enqueue(db, user_id=booking.musician.user_id,
                event_key=f"payout_transferred:{booking.id}", kind="payment",
                title="Pago liberado",
                body="El pago de tu evento fue enviado a tu cuenta.",
                data={"booking_id": str(booking.id)})
        db.commit()
        return True
    destination = db.scalar(select(MusicianPayoutDestination).where(
        MusicianPayoutDestination.musician_id == booking.musician_id
    ))
    if (not destination or not destination.stripe_connected_account_id
            or not destination.stripe_payouts_enabled):
        booking.payout_status = "pending_connect_account"
        booking.payout_error = "La cuenta Stripe Connect aún no está habilitada para depósitos"
        db.commit()
        return False
    if not booking.stripe_payment_intent_id:
        booking.payout_status = "transfer_failed"
        booking.payout_error = "El cobro no tiene PaymentIntent de Stripe"
        db.commit()
        return False


    try:
        stripe_client_ready()
        payment_intent = stripe.PaymentIntent.retrieve(
            booking.stripe_payment_intent_id
        )
        latest_charge = getattr(payment_intent, "latest_charge", None)
        if isinstance(latest_charge, dict):
            latest_charge = latest_charge.get("id")
        elif latest_charge and not isinstance(latest_charge, str):
            latest_charge = getattr(latest_charge, "id", None)
        if not latest_charge:
            raise ValueError("Stripe no devolvió el cargo asociado")
        transfer = stripe.Transfer.create(
            amount=booking.musician_earnings_cents,
            currency=booking.currency,
            destination=destination.stripe_connected_account_id,
            source_transaction=latest_charge,
            transfer_group=f"balam_booking_{booking.id}",
            description=f"Balam contrato #{booking.id}",
            metadata={"booking_id": str(booking.id),
                      "musician_id": str(booking.musician_id)},
            idempotency_key=f"balam-booking-{booking.id}-musician-v1",
        )
        booking.stripe_transfer_id = transfer.id
        booking.payout_status = "transferred"
        booking.payout_error = None
        enqueue(db, user_id=booking.musician.user_id,
                event_key=f"payout_transferred:{booking.id}", kind="payment",
                title="Pago liberado",
                body="El pago de tu evento fue enviado a tu cuenta.",
                data={"booking_id": str(booking.id)})
        db.commit()
        return True
    except (stripe.error.StripeError, ValueError, HTTPException) as error:
        db.rollback()
        booking = db.get(Booking, booking_id)
        booking.payout_status = "transfer_failed"
        booking.payout_error = str(error)[:1000]
        db.commit()
        return False


def payout_release_deadline(booking: Booking) -> datetime:
    """Moment when the client's review/dispute window closes."""
    event_timezone = ZoneInfo(settings.event_timezone)
    event_ends_at = datetime.combine(
        booking.event_date, booking.end_time, tzinfo=event_timezone
    )
    return event_ends_at + timedelta(hours=settings.payout_auto_release_hours)


def release_due_payouts(db: Session, *, now: datetime | None = None) -> int:
    """Authorize and transfer every undisputed payment whose window has expired."""
    event_timezone = ZoneInfo(settings.event_timezone)
    current_time = now or datetime.now(event_timezone)
    if current_time.tzinfo is None:
        current_time = current_time.replace(tzinfo=event_timezone)
    else:
        current_time = current_time.astimezone(event_timezone)

    candidate_ids = list(db.scalars(select(Booking.id).where(
        Booking.payment_status == "paid",
        Booking.payout_status == "musician_funds_held",
    )))
    released = 0
    approved_at = current_time.astimezone(timezone.utc).replace(tzinfo=None)
    for booking_id in candidate_ids:
        booking = db.get(Booking, booking_id)
        if not booking or current_time < payout_release_deadline(booking):
            continue
        result = db.execute(
            update(Booking)
            .where(
                Booking.id == booking_id,
                Booking.payment_status == "paid",
                Booking.payout_status == "musician_funds_held",
            )
            .values(
                payout_status="approved_for_payout",
                approved_for_payout_at=approved_at,
            )
        )
        db.commit()
        if result.rowcount == 1:
            release_musician_funds(booking_id, db)
            released += 1
    return released


@router.post("/webhooks/stripe", include_in_schema=False)
async def stripe_webhook(request: Request, db: Session = Depends(get_db)):
    if not settings.stripe_webhook_secret:
        raise HTTPException(503, "Webhook de Stripe no configurado")
    payload = bytearray()
    async for chunk in request.stream():
        payload.extend(chunk)
        if len(payload) > settings.max_stripe_webhook_bytes:
            raise HTTPException(413, "Webhook demasiado grande")
    try:
        event = stripe.Webhook.construct_event(
            bytes(payload), request.headers.get("stripe-signature", ""), settings.stripe_webhook_secret
        )
    except (ValueError, stripe.error.SignatureVerificationError):
        raise HTTPException(400, "Firma de webhook inválida")

    processed = StripeWebhookEvent(
        stripe_event_id=event["id"], event_type=event["type"]
    )
    db.add(processed)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return {"received": True, "duplicate": True}

    event_type = event["type"]
    if event_type.startswith("checkout.session."):
        sync_checkout(event["type"], event["data"]["object"], db)
    elif event_type in {"refund.updated", "refund.failed"}:
        refund = stripe_object_dict(event["data"]["object"])
        booking = db.scalar(select(Booking).where(
            Booking.stripe_payment_intent_id == refund.get("payment_intent"),
            Booking.payout_status == "date_conflict",
        ).with_for_update()) if refund.get("payment_intent") else None
        if booking:
            status = refund.get("status")
            if status == "succeeded":
                booking.payment_status = "refunded"
                enqueue(db, user_id=booking.client.user_id,
                        event_key=f"booking_refunded:{booking.id}", kind="payment",
                        title="Reembolso confirmado",
                        body="Stripe confirmó el reembolso de tu contratación por conflicto de fecha.",
                        data={"booking_id": str(booking.id)})
            elif status in {"failed", "canceled"}:
                booking.payment_status = "refund_failed"
                for admin in db.scalars(select(User).where(
                    User.role == UserRole.admin, User.is_active.is_(True),
                )):
                    enqueue(db, user_id=admin.id,
                            event_key=f"booking_refund_failed:{booking.id}", kind="payment",
                            title="Reembolso requiere atención",
                            body=f"Stripe no pudo completar el reembolso de la contratación #{booking.id}. Revisa el pago en Stripe.",
                            data={"booking_id": str(booking.id)})
    elif event_type == "account.updated":
        destination = sync_connect_account(event["data"]["object"], db)
        db.flush()
        if destination and destination.stripe_payouts_enabled:
            pending_ids = list(db.scalars(select(Booking.id).where(
                Booking.musician_id == destination.musician_id,
                Booking.payout_status == "pending_connect_account",
                Booking.approved_for_payout_at.is_not(None),
            )).all())
            db.commit()
            for booking_id in pending_ids:
                pending = db.get(Booking, booking_id)
                pending.payout_status = "approved_for_payout"
                pending.payout_error = None
                db.commit()
                release_musician_funds(booking_id, db)
            return {"received": True, "retried_transfers": len(pending_ids)}
    elif event_type in {"payout.paid", "payout.failed"}:
        payout = stripe_object_dict(event["data"]["object"])
        connected_account_id = event.get("account")
        destination = db.scalar(select(MusicianPayoutDestination).where(
            MusicianPayoutDestination.stripe_connected_account_id == connected_account_id
        ))
        if destination:
            destination.last_stripe_payout_id = payout.get("id")
            destination.last_stripe_payout_status = (
                "paid" if event_type == "payout.paid" else "failed"
            )
            destination.last_stripe_payout_error = (
                None if event_type == "payout.paid" else
                (payout.get("failure_message") or payout.get("failure_code") or
                 "Stripe no pudo completar el depósito bancario")
            )
    db.commit()
    return {"received": True}
