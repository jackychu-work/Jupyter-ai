"""JupyterHub config: one notebook container per user, spawned on the local Docker daemon.

Everything is env-overridable so the same file works for a plain
`docker compose up` and for a smoke test.
"""

import os

c = get_config()  # noqa: F821

network_name = os.environ.get("DOCKER_NETWORK_NAME", "jupyterhub-network")

# ---------------------------------------------------------------- spawner
c.JupyterHub.spawner_class = "dockerspawner.DockerSpawner"
c.DockerSpawner.image = os.environ.get("DOCKER_NOTEBOOK_IMAGE", "jupyter-ai:local")
c.DockerSpawner.network_name = network_name
# Containers talk to the hub over the user-defined network, not via host ports.
c.DockerSpawner.use_internal_ip = True
c.DockerSpawner.pull_policy = os.environ.get("DOCKER_NOTEBOOK_PULL_POLICY", "ifnotpresent")
c.DockerSpawner.remove = True
c.DockerSpawner.debug = True

# Named volume per user, mounted at the notebook root. A fresh docker volume
# inherits ownership from the image's /home/jovyan/work (uid 1000), so jovyan
# can write without running the container as root.
notebook_dir = os.environ.get("DOCKER_NOTEBOOK_DIR", "/home/jovyan/work")
c.Spawner.notebook_dir = notebook_dir
c.DockerSpawner.volumes = {"jupyterhub-user-{username}": notebook_dir}

# AI gateway endpoint + key for the opencode provider (see opencode.config.json
# in the image). Same names as the documented per-user /home/jovyan/.env; passed
# through to spawned containers only when provided here.
_gateway_env = {
    k: os.environ[k]
    for k in ("OPENAI_API_BASE", "OPENAI_API_KEY")
    if os.environ.get(k)
}
if _gateway_env:
    c.DockerSpawner.environment = _gateway_env

# Optional per-container cap, e.g. SPAWN_MEM_LIMIT=8G on a laptop.
if os.environ.get("SPAWN_MEM_LIMIT"):
    c.DockerSpawner.mem_limit = os.environ["SPAWN_MEM_LIMIT"]

# ---------------------------------------------------------------- hub net
# Hub API listens on all interfaces inside its container; spawned containers
# resolve it by container name on the shared network.
c.JupyterHub.hub_ip = "0.0.0.0"
c.JupyterHub.hub_connect_ip = os.environ.get("HUB_CONNECT_NAME", "jupyterhub")
c.JupyterHub.hub_port = 8081
# Public entrypoint = configurable-http-proxy inside the hub container.
c.JupyterHub.bind_url = "http://0.0.0.0:8000"

# ---------------------------------------------------------------- state
c.JupyterHub.cookie_secret_file = "/data/jupyterhub_cookie_secret"
c.JupyterHub.db_url = "sqlite:////data/jupyterhub.sqlite"

# ---------------------------------------------------------------- auth
# Local testing only: any username + any password.
c.JupyterHub.authenticator_class = "dummy"
c.Authenticator.allow_all = True
c.Authenticator.admin_users = [
    u.strip() for u in os.environ.get("JUPYTERHUB_ADMIN", "admin").split(",") if u.strip()
]
# Note: scripted tests use the cookie/xsrf login flow (hub/smoke-test.sh),
# matching what a browser does; no static API tokens are provisioned.
