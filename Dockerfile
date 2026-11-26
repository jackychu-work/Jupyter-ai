# Stage 1: Builder to prepare Flink and dependencies
FROM flink:1.20.5-scala_2.12 AS flink-builder

# Stage 2: Final image
FROM quay.io/jupyter/datascience-notebook:python-3.13

USER root

# Install runtime dependencies and apply all available security updates.
#   - ffmpeg (deb) is not required by the stack -> remove to cut scanner findings
#   - nodejs is installed from conda-forge below (avoids the ~880 Debian node-* packages)
RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
    sssd libltdl7 libkrb5-3 libgssapi-krb5-2 gnupg2 unixodbc unixodbc-dev odbcinst tdsodbc libkrb5-dev libssl-dev ca-certificates dirmngr gpg-agent wget curl \
    openjdk-11-jdk-headless bsdextrautils && \
    apt-get remove -y ffmpeg && \
    apt-get autoremove -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=$JAVA_HOME/bin:$PATH
ENV FLINK_HOME=/opt/flink

# Copy Flink from builder and create symlink
COPY --from=flink-builder ${FLINK_HOME} ${FLINK_HOME}
RUN ln -s ${FLINK_HOME}/bin/flink /usr/local/bin/flink && mkdir -p ${FLINK_HOME}/plugins/s3-fs-hadoop

# Download compatible Paimon, Flink SQL Client, and S3 connector JARs into /opt/flink/lib
# Paimon 1.4.2 (not 1.3.2) for its bundled httpclient5 5.5.1 / aircompressor 2.0.3 /
# commons-lang3 3.18.0, which clear three Clair findings; jackson 2.14.3 and
# protobuf-java 3.19.6 are unchanged upstream, and httpcore5 5.3.6 is still below
# the 5.4.3 fix.
RUN wget -O ${FLINK_HOME}/lib/paimon-flink-1.20-1.4.2.jar https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-flink-1.20/1.4.2/paimon-flink-1.20-1.4.2.jar && \
    wget -O ${FLINK_HOME}/lib/paimon-s3-1.4.2.jar https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-s3/1.4.2/paimon-s3-1.4.2.jar && \
    wget -O ${FLINK_HOME}/lib/flink-sql-client-1.20.5.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-client/1.20.5/flink-sql-client-1.20.5.jar && \
    wget -O ${FLINK_HOME}/lib/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar && \
    wget -O ${FLINK_HOME}/plugins/s3-fs-hadoop/flink-s3-fs-hadoop-1.20.5.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-s3-fs-hadoop/1.20.5/flink-s3-fs-hadoop-1.20.5.jar && \
    wget -O ${FLINK_HOME}/lib/flink-parquet-1.20.5.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-parquet/1.20.5/flink-parquet-1.20.5.jar

# Connectors/drivers required by the reference runtime (/opt/flink/lib listing):
# JDBC + MySQL driver, MySQL/SQLServer CDC SQL connectors, unshaded Hadoop 3.4.0 client jars.
RUN wget -O ${FLINK_HOME}/lib/flink-connector-jdbc-core-3.3.0-1.20.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-connector-jdbc-core/3.3.0-1.20/flink-connector-jdbc-core-3.3.0-1.20.jar && \
    wget -O ${FLINK_HOME}/lib/mysql-connector-j-9.3.0.jar https://repo.maven.apache.org/maven2/com/mysql/mysql-connector-j/9.3.0/mysql-connector-j-9.3.0.jar && \
    wget -O ${FLINK_HOME}/lib/flink-sql-connector-mysql-cdc-3.5.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-mysql-cdc/3.5.0/flink-sql-connector-mysql-cdc-3.5.0.jar && \
    wget -O ${FLINK_HOME}/lib/flink-sql-connector-sqlserver-cdc-3.5.0.jar https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-sqlserver-cdc/3.5.0/flink-sql-connector-sqlserver-cdc-3.5.0.jar && \
    wget -O ${FLINK_HOME}/lib/hadoop-common-3.4.0.jar https://repo.maven.apache.org/maven2/org/apache/hadoop/hadoop-common/3.4.0/hadoop-common-3.4.0.jar && \
    wget -O ${FLINK_HOME}/lib/hadoop-hdfs-client-3.4.0.jar https://repo.maven.apache.org/maven2/org/apache/hadoop/hadoop-hdfs-client/3.4.0/hadoop-hdfs-client-3.4.0.jar && \
    wget -O ${FLINK_HOME}/lib/hadoop-mapreduce-client-core-3.4.0.jar https://repo.maven.apache.org/maven2/org/apache/hadoop/hadoop-mapreduce-client-core/3.4.0/hadoop-mapreduce-client-core-3.4.0.jar

# Replace the vulnerable log4j 2.24.3 jars bundled with the Flink 1.20.5 distro (CVE fixes).
# flink-table-api-java-uber / planner-loader / runtime come from the distro at 1.20.5, no override needed.
RUN cd ${FLINK_HOME}/lib && \
    wget -O log4j-api-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-api/2.25.5/log4j-api-2.25.5.jar && \
    wget -O log4j-core-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-core/2.25.5/log4j-core-2.25.5.jar && \
    wget -O log4j-1.2-api-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-1.2-api/2.25.5/log4j-1.2-api-2.25.5.jar && \
    wget -O log4j-slf4j-impl-2.25.5.jar https://repo.maven.apache.org/maven2/org/apache/logging/log4j/log4j-slf4j-impl/2.25.5/log4j-slf4j-impl-2.25.5.jar && \
    rm -f log4j-api-2.24.3.jar log4j-core-2.24.3.jar log4j-1.2-api-2.24.3.jar log4j-slf4j-impl-2.24.3.jar && \
    chown -R ${NB_UID}:${NB_GID} ${FLINK_HOME}

# Consolidate Flink config and permissions
RUN mkdir -p /home/jovyan/.flink/logs /home/jovyan/.flink/pids && \
    chown -R ${NB_UID}:${NB_GID} ${FLINK_HOME} /home/jovyan/.flink

# The python-3.13 base already ships current builds (python 3.13.18, openssl 3.6.5).
# Install a maintained Node.js 22 from conda-forge instead of the Debian node-* packages.
# opencode-ai backs the @OpenCode ACP persona from jupyter-ai-acp-client
# (`opencode acp`, protocol v1); /etc/opencode disables self-update in the image.
RUN mamba install -y -n base -c conda-forge "nodejs=22" && \
    mamba clean -ay && \
    rm -rf /usr/local/lib/node_modules /usr/local/bin/configurable-http-proxy /usr/local/bin/glob && \
    npm install -g configurable-http-proxy cross-spawn@^7.0.5 glob@^10.5.0 requirejs@^2.3.7 npm@11 opencode-ai@1.19.6 && \
    npm cache clean --force && \
    rm -rf /opt/conda/pkgs /home/jovyan/.npm && \
    mkdir -p /etc/opencode && \
    printf '%s\n' '{"$schema":"https://opencode.ai/config.json","autoupdate":false}' > /etc/opencode/opencode.json && \
    chown -R ${NB_UID}:${NB_GID} /opt/conda /home/jovyan

# Set Flink environment variables
ENV FLINK_LOG_DIR=/home/jovyan/.flink/logs
ENV FLINK_PID_DIR=/home/jovyan/.flink/pids

USER ${NB_UID}

# Install Python dependencies
COPY --chown=${NB_UID}:${NB_GID} requirements.txt /tmp/requirements.txt
COPY --chown=${NB_UID}:${NB_GID} requirements-overrides.txt /tmp/requirements-overrides.txt
RUN pip install --no-cache-dir uv && \
    uv pip install --system --no-cache-dir \
      -r /tmp/requirements.txt \
      --overrides /tmp/requirements-overrides.txt && \
    rm /tmp/requirements.txt /tmp/requirements-overrides.txt

# Present the ACP persona as "Sands AI" instead of "OpenCode". PersonaManager
# exposes no rename or filter knob, and entry-point personas are concatenated
# with local ones, so a subclass alone would list a second "OpenCode" persona.
# Repointing the `opencode-acp` entry point keeps exactly one persona.
COPY --chown=${NB_UID}:${NB_GID} sands_persona.py sands-logo.svg /tmp/
RUN SP="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" && \
    install -m 0644 /tmp/sands_persona.py /tmp/sands-logo.svg "${SP}/" && \
    if [ ! -s "${SP}/sands-logo.svg" ]; then echo "sands-logo.svg missing or empty" >&2; exit 1; fi && \
    python -c 'import pathlib, sys; sp = pathlib.Path(sys.argv[1]); ep = next(sp.glob("jupyter_ai_acp_client-*.dist-info/entry_points.txt")); old = "opencode-acp = jupyter_ai_acp_client.acp_personas.opencode:OpenCodeAcpPersona"; new = "opencode-acp = sands_persona:SandsAssistantPersona"; text = ep.read_text(); assert old in text, "opencode-acp entry point not found in %s" % ep; ep.write_text(text.replace(old, new))' "${SP}" && \
    rm /tmp/sands_persona.py /tmp/sands-logo.svg

# Python 3.12 fallback kernel. The server, jupyter-ai and the MCP tool stack
# stay on the base 3.13 interpreter; this env only backs the "Python 3.12"
# kernelspec for user code that has no 3.13 wheels yet. -p keeps mamba out of
# the base env at /opt/conda, so 3.13 packages are never touched. The science
# packages mirror the base image's Python stack (R/Julia stay 3.13-side only).
RUN mamba create -y -p /opt/conda/envs/py312 \
      python=3.12 ipykernel pip \
      numpy pandas scipy matplotlib-base seaborn scikit-learn \
      statsmodels sympy numba bokeh altair ipywidgets && \
    /opt/conda/envs/py312/bin/python -m ipykernel install \
      --prefix /opt/conda --name python312 --display-name "Python 3.12" && \
    mamba clean --all -f -y && \
    rm -rf /opt/conda/pkgs

# AI gateway as an opencode provider. Nothing secret is baked in: the endpoint
# and the model-scoped virtual key come from OPENAI_API_BASE / OPENAI_API_KEY,
# which the startup hook exports from /home/jovyan/.env (the documented
# deployment contract). Only models the gateway actually serves are declared
# (verified 2026-11-26).
COPY --chown=${NB_UID}:${NB_GID} opencode.config.json /tmp/opencode.config.json
RUN mkdir -p /home/jovyan/.config/opencode && \
    mv /tmp/opencode.config.json /home/jovyan/.config/opencode/opencode.json && \
    chown -R ${NB_UID}:${NB_GID} /home/jovyan/.config/opencode

# No CA and no endpoint is baked in. If the deployment's TLS surface uses a
# private root, mount PEM certificates at /home/jovyan/.certs/*.crt (read-only
# is fine); startup-env.sh merges them into /home/jovyan/.ca-bundle.crt and
# exports NODE_EXTRA_CA_CERTS / SSL_CERT_FILE / CURL_CA_BUNDLE for the notebook
# server and the ACP child without needing root. DER is not supported.
USER root
RUN mkdir -p /home/jovyan/.certs && chown ${NB_UID}:${NB_GID} /home/jovyan/.certs

# outputTokenMax is a single global flag (opencode >=1.19.6): the per-request
# max_tokens is min(limit.output, OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX), and
# that flag defaults to 32000. Raise it above the largest per-model limit so
# each model's own limit.output decides (DeepSeek 64K, Qwen 128K); the
# compaction threshold is then context - limit.output = the model's input budget.
ENV OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX=131072

# start.sh sources every *.sh in start-notebook.d, so exporting ~/.env here is
# what makes OPENAI_API_BASE / OPENAI_API_KEY visible to the ACP persona.
COPY --chmod=0644 startup-env.sh /usr/local/bin/start-notebook.d/10-ai-gateway-env.sh
USER ${NB_UID}

WORKDIR ${HOME}
