"""Offline geographic lookup used by Surprise Group matching.

The bundled INEGI municipal-capital catalog keeps the client flow simple and
does not make a booking depend on a paid geocoding provider.  Coordinates are
an approximation of the municipality's municipal seat, not a street address.
"""

from functools import lru_cache
import json
from pathlib import Path
import re
import unicodedata


def normalize_place(value: str | None) -> str:
    value = unicodedata.normalize("NFKD", (value or ""))
    value = "".join(char for char in value if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


STATE_ALIASES = {
    "cdmx": "ciudad de mexico",
    "distrito federal": "ciudad de mexico",
    "coahuila": "coahuila de zaragoza",
    "edomex": "mexico",
    "estado de mexico": "mexico",
    "michoacan": "michoacan de ocampo",
    "nuevo leon": "nuevo leon",
    "veracruz": "veracruz de ignacio de la llave",
}


@lru_cache(maxsize=1)
def _municipal_capitals() -> dict[tuple[str, str], tuple[float, float]]:
    source = Path(__file__).with_name("data") / "inegi_municipal_capitals.json"
    rows = json.loads(source.read_text(encoding="utf-8"))
    return {
        (normalize_place(row["state"]), normalize_place(row["municipality"])): (
            float(row["latitude"]), float(row["longitude"])
        )
        for row in rows
    }


def municipality_coordinates(
    state: str | None, municipality: str | None,
) -> tuple[float, float] | None:
    """Return an approximate municipal location without calling external APIs."""
    normalized_state = normalize_place(state)
    normalized_state = STATE_ALIASES.get(normalized_state, normalized_state)
    return _municipal_capitals().get((normalized_state, normalize_place(municipality)))
