import stripe
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .auth import current_user
from .config import settings
from .database import get_db
from .models import BillingCustomer, Booking, StripeWebhookEvent, User

router = APIRouter(prefix="/api/billing", tags=["billing"])


class CheckoutRequest(BaseModel):
    booking_id: int


def checkout_return_page(*, paid: bool) -> HTMLResponse:
    if paid:
        title = "Pago completado"
        message = "Tu pago fue procesado. Ya puedes volver a Balam."
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
    return checkout_return_page(paid=True)


@router.get("/checkout/cancel", response_class=HTMLResponse)
def checkout_cancel():
    return checkout_return_page(paid=False)


def stripe_client_ready() -> None:
    if not settings.stripe_secret_key:
        raise HTTPException(503, "Stripe Billing no está configurado")
    stripe.api_key = settings.stripe_secret_key


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
    stripe_client_ready()
    booking = db.get(Booking, data.booking_id)
    if not booking:
        raise HTTPException(404, "Contratación no encontrada")
    if booking.client.user_id != user.id:
        raise HTTPException(403, "Esta contratación pertenece a otro cliente")
    if booking.payment_status == "paid":
        raise HTTPException(409, "Esta contratación ya está pagada")
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
    customer = customer_for(user, db)
    session = stripe.checkout.Session.create(
        mode="payment",
        customer=customer.stripe_customer_id,
        line_items=[{
            "price_data": {
                "currency": booking.currency,
                "unit_amount": booking.total_cents,
                "product_data": {
                    "name": f"Contratación de {booking.musician.group_name}",
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
            "metadata": {"balam_user_id": str(user.id), "booking_id": str(booking.id)}
        },
        invoice_creation={"enabled": True},
        billing_address_collection="required",
    )
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
    if event_type in {"checkout.session.completed", "checkout.session.async_payment_succeeded"}:
        if obj.get("payment_status") in {"paid", "no_payment_required"}:
            booking.payment_status = "paid"
            booking.stripe_payment_intent_id = obj.get("payment_intent")
    elif event_type == "checkout.session.async_payment_failed":
        booking.payment_status = "failed"
    elif event_type == "checkout.session.expired" and booking.payment_status != "paid":
        booking.payment_status = "expired"


@router.post("/webhooks/stripe", include_in_schema=False)
async def stripe_webhook(request: Request, db: Session = Depends(get_db)):
    if not settings.stripe_webhook_secret:
        raise HTTPException(503, "Webhook de Stripe no configurado")
    payload = await request.body()
    try:
        event = stripe.Webhook.construct_event(
            payload, request.headers.get("stripe-signature", ""), settings.stripe_webhook_secret
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

    if event["type"].startswith("checkout.session."):
        sync_checkout(event["type"], event["data"]["object"], db)
    db.commit()
    return {"received": True}
