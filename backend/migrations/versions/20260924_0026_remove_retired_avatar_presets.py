"""Replace retired avatar selections with an available musician avatar."""

from alembic import op
import sqlalchemy as sa


revision = "20260924_0026"
down_revision = "20260923_0025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    avatar_choices = sa.table(
        "avatar_choices",
        sa.column("preset", sa.String),
    )
    retired_presets = (
        "musician_guitar_eden",
        "musician_guitar_chalino",
        "jaguar_guitar",
        "jaguar_accordion",
        "jaguar_dj",
        "coyote_singer",
        "coyote_guitar",
        "coyote_drums",
        "owl_violin",
        "owl_keyboard",
        "owl_sax",
        "fox_bass",
        "fox_mariachi",
        "fox_singer",
        "bear_tuba",
        "bear_drums",
        "bear_accordion",
        "eagle_trumpet",
        "eagle_guitar",
        "eagle_dj",
        "rabbit_violin",
        "lion_trumpet",
        "lion_conductor",
        "lion_tuba",
        "axolotl_guitar",
        "axolotl_dj",
        "raccoon_bass",
        "deer_harp",
        "bull_trombone",
        "cat_violin",
        "elephant_cello",
        "turtle_flute",
    )
    op.execute(
        avatar_choices.update()
        .where(avatar_choices.c.preset.in_(retired_presets))
        .values(preset="musician_singer_black")
    )


def downgrade() -> None:
    # The original choice cannot be determined after the replacement.
    pass
