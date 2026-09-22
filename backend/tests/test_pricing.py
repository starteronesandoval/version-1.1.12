"""Rules for normal, local, and low-season booking prices."""
from datetime import date

import pytest
from pydantic import ValidationError

from app.main import selected_hourly_rate
from app.models import ClientProfile, MusicianProfile
from app.schemas import MusicianProfileUpsert


def musician(**overrides):
    values = dict(
        contact_name="Ana", group_name="Grupo", group_type="Banda",
        musical_style="Regional", member_count=4, hourly_rate=1000,
        city="Monterrey", municipality="Monterrey", state="Nuevo León",
        equipment_brands="[]", description="",
        local_hourly_rate=800, low_season_hourly_rate=650,
        low_season_dates='["2099-10-19"]',
    )
    values.update(overrides)
    return MusicianProfile(**values)


def client(**overrides):
    values = dict(name="Luis", city="Monterrey", municipality="Monterrey", state="Nuevo León")
    values.update(overrides)
    return ClientProfile(**values)


def test_low_season_has_priority_over_local_price():
    assert selected_hourly_rate(musician(), client(), date(2099, 10, 19)) == (650.0, "low_season")


def test_local_price_requires_an_exact_city_or_municipality_match():
    assert selected_hourly_rate(musician(), client(), date(2099, 10, 20)) == (800.0, "local")
    assert selected_hourly_rate(
        musician(), client(city="Guadalupe", municipality="Guadalupe"), date(2099, 10, 20)
    ) == (1000.0, "normal")


def test_low_season_dates_exclude_weekends_and_protected_months():
    profile = dict(
        contact_name="Ana", group_name="Grupo", group_type="Banda",
        musical_style="Regional", member_count=4, hourly_rate=1000,
    )
    assert MusicianProfileUpsert(**profile, low_season_dates=[date(2099, 10, 19)])
    for unavailable in (date(2099, 10, 23), date(2099, 5, 3), date(2099, 12, 7)):
        with pytest.raises(ValidationError):
            MusicianProfileUpsert(**profile, low_season_dates=[unavailable])
