"""Seed an isolated local demo database; never use against production."""

from sqlalchemy import select

from app.auth import hash_password
from app.database import SessionLocal
from app.geography import municipality_coordinates
from app.models import ClientProfile, MusicianProfile, User, UserRole


GROUP_EMAIL = "estilo-libre.demo@balam.local"
CLIENT_EMAIL = "cliente.demo@balam.local"
PASSWORD = "PruebaBalam2026!"

# Approximate offsets from Cocula.  Every group stays safely within the
# product ceiling of 30 km for an event located in Cocula.
DEMO_GROUPS = (
    ("Estilo Libre", "estilo-libre.demo@balam.local", 0.000, 0.000, 2700),
    ("Norte Claro", "norte-claro.demo@balam.local", 0.040, 0.020, 2600),
    ("Banda Sierra Viva", "banda-sierra-viva.demo@balam.local", -0.055, 0.025, 2800),
    ("Los Caminantes del Valle", "caminantes-valle.demo@balam.local", 0.090, -0.035, 2500),
    ("Regional Luna", "regional-luna.demo@balam.local", -0.120, -0.050, 2900),
    ("Sones del Sur", "sones-sur.demo@balam.local", 0.135, 0.060, 2650),
)


def get_or_create_user(db, email: str, role: UserRole) -> User:
    user = db.scalar(select(User).where(User.email == email))
    if user:
        return user
    user = User(email=email, password_hash=hash_password(PASSWORD), role=role)
    db.add(user)
    db.flush()
    return user


def main() -> None:
    cocula = municipality_coordinates("Jalisco", "Cocula")
    if not cocula:
        raise RuntimeError("No se encontró Cocula, Jalisco en el catálogo local")
    with SessionLocal() as db:
        for index, (name, email, latitude_offset, longitude_offset, rate) in enumerate(DEMO_GROUPS):
            group_user = get_or_create_user(db, email, UserRole.musician)
            group = db.scalar(select(MusicianProfile).where(MusicianProfile.user_id == group_user.id))
            group_data = dict(
                contact_name=f"Administración {name}",
                admin_phone=f"33111111{index:02d}",
                city="Cocula", municipality="Cocula", state="Jalisco",
                group_name=name, group_type="Norteño Banda",
                musical_style="Norteño, banda y regional mexicano",
                member_count=5, hourly_rate=rate, minimum_booking_hours=3,
                equipment_brands="[]", description="Agrupación de prueba local",
                surprise_group_enabled=True,
                base_latitude=cocula[0] + latitude_offset,
                base_longitude=cocula[1] + longitude_offset,
                radio_servicio_sorpresa_km=30,
            )
            if group:
                for key, value in group_data.items():
                    setattr(group, key, value)
            else:
                db.add(MusicianProfile(user_id=group_user.id, **group_data))

        client_user = get_or_create_user(db, CLIENT_EMAIL, UserRole.client)
        client = db.scalar(select(ClientProfile).where(ClientProfile.user_id == client_user.id))
        client_data = dict(
            name="Cliente de prueba", admin_phone="3311111112",
            city="Cocula", municipality="Cocula", state="Jalisco",
            location_latitude=cocula[0], location_longitude=cocula[1],
            musical_tastes="Norteño", favorite_groups="[]",
        )
        if client:
            for key, value in client_data.items():
                setattr(client, key, value)
        else:
            db.add(ClientProfile(user_id=client_user.id, **client_data))
        db.commit()
    print(f"Demo local lista. Cliente: {CLIENT_EMAIL} / {PASSWORD}")
    print("Seis agrupaciones elegibles en Cocula, Jalisco, radio máximo 30 km")


if __name__ == "__main__":
    main()
