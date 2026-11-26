"""Present the OpenCode ACP persona as "Sands AI" in Jupyter AI.

The visible name is `BasePersona.defaults.name`; the built-in ACP persona
hardcodes it as "OpenCode". `PersonaManager` has no rename knob and no
allow/deny list (only `default_persona_id` and `builtin_mcp_servers`), and it
concatenates entry-point personas with local ones — so shipping this subclass
alongside the built-in one would show *two* personas, one still named
"OpenCode".

The image therefore repoints the `opencode-acp` entry point at this class
instead of `jupyter_ai_acp_client.acp_personas.opencode:OpenCodeAcpPersona`.
That leaves exactly one ACP persona, labelled "Sands AI".

Re-apply after upgrading `jupyter_ai_acp_client`: the entry point lives in that
distribution's `entry_points.txt`, which pip regenerates.
"""

import os

from jupyter_ai_acp_client.acp_personas.opencode import OpenCodeAcpPersona

# Brand asset installed next to this module by the Dockerfile. `avatar_path` is
# an absolute filesystem path; the persona manager caches it at startup and
# serves it at `{base_url}api/ai/avatars/{persona_id}` (any SVG/PNG, <= 5 MB).
AVATAR_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "sands-logo.svg"
)


class SandsAssistantPersona(OpenCodeAcpPersona):
    """OpenCode ACP persona presented under the Sands China brand."""

    @property
    def defaults(self):
        return super().defaults.model_copy(
            update={
                "name": "Sands AI",
                "description": "Sands AI assistant.",
                "avatar_path": AVATAR_PATH,
            }
        )
