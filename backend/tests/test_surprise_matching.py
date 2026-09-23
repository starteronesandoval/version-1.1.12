import os
from types import SimpleNamespace

os.environ["DATABASE_URL"] = "sqlite:///./test_balam.db"
os.environ["UPLOAD_DIR"] = "test_uploads"
os.environ["APP_ENV"] = "test"
os.environ["SECRET_KEY"] = "test-only-secret-key-with-at-least-32-characters"
os.environ["EXPOSE_PASSWORD_RESET_CODE"] = "true"

from app.main import (
    _haversine_distance_km,
    event_distance_km,
    _matches_surprise_genre,
    _same_service_zone,
    _surprise_rate_is_eligible,
    _weighted_surprise_candidates,
)
from app.geography import municipality_coordinates


def musician(**changes):
    values = {
        "group_type": "Norteño",
        "musical_style": "Norteño tradicional",
        "city": "Cocula",
        "municipality": "Cocula",
        "state": "Jalisco",
        "base_latitude": 20.6597,
        "base_longitude": -103.3496,
    }
    values.update(changes)
    return SimpleNamespace(**values)


def client(**changes):
    values = {
        "city": "Cocula",
        "municipality": "Cocula",
        "state": "Jalisco",
    }
    values.update(changes)
    return SimpleNamespace(**values)


def test_rate_accepts_exact_budget_and_up_to_500_below():
    assert _surprise_rate_is_eligible(2500, 2500)
    assert _surprise_rate_is_eligible(2499.99, 2500)
    assert _surprise_rate_is_eligible(2000, 2500)


def test_rate_rejects_above_budget_or_more_than_500_below():
    assert not _surprise_rate_is_eligible(2500.01, 2500)
    assert not _surprise_rate_is_eligible(1999.99, 2500)
    assert not _surprise_rate_is_eligible(0, 2500)


def test_genre_matching_ignores_case_and_accents():
    profile = musician(group_type="NORTEÑO", musical_style="Norteño romántico")
    assert _matches_surprise_genre(profile, "norteno")
    assert _matches_surprise_genre(profile, "Norteño")
    assert not _matches_surprise_genre(profile, "Mariachi")


def test_otros_excludes_the_named_main_genres():
    assert not _matches_surprise_genre(musician(), "Otros")
    assert _matches_surprise_genre(
        musician(group_type="Versátil", musical_style="Cumbia y salsa"),
        "Otros",
    )


def test_zone_matching_ignores_case_and_accents_but_requires_same_state():
    profile = musician(city="Concepción de Buenos Aires", state="Jalisco")
    customer = client(
        city="concepcion de buenos aires",
        municipality="Otra localidad",
        state="JALISCO",
    )
    assert _same_service_zone(profile, customer)
    customer.state = "Colima"
    assert not _same_service_zone(profile, customer)


def test_zone_requires_a_city_or_municipality_intersection():
    assert not _same_service_zone(
        musician(city="Cocula", municipality="Cocula"),
        client(city="Guadalajara", municipality="Guadalajara"),
    )


def test_haversine_distance_is_symmetric_and_uses_kilometers():
    guadalajara = (20.6597, -103.3496)
    mexico_city = (19.4326, -99.1332)
    distance = _haversine_distance_km(*guadalajara, *mexico_city)
    assert 450 < distance < 470
    assert round(distance, 6) == round(_haversine_distance_km(*mexico_city, *guadalajara), 6)


def test_event_distance_uses_base_coordinates_and_allows_future_provider_swap():
    profile = musician(base_latitude=20.6597, base_longitude=-103.3496)
    assert event_distance_km(profile, 20.6597, -103.3496) == 0
    assert event_distance_km(musician(base_latitude=None), 20.6597, -103.3496) is None


def test_offline_catalog_resolves_municipality_without_coordinates_from_client():
    monterrey = municipality_coordinates("Nuevo León", "Monterrey")
    assert monterrey is not None
    assert 25 < monterrey[0] < 26
    assert -101 < monterrey[1] < -100


def test_estilo_libre_has_three_entries_after_passing_all_filters():
    estilo_libre = musician(group_name="Estilo Libre")
    another_group = musician(group_name="Norte Claro")
    weighted = _weighted_surprise_candidates([
        (estilo_libre, 2700, "normal", 0.0),
        (another_group, 2600, "normal", 4.0),
    ])
    assert sum(item[0].group_name == "Estilo Libre" for item in weighted) == 3
    assert sum(item[0].group_name == "Norte Claro" for item in weighted) == 1
