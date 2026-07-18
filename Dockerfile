ARG AGENT_TAG=latest
FROM nousresearch/hermes-agent:${AGENT_TAG}

ARG WEBUI_REPO=https://github.com/nesquena/hermes-webui.git
ARG WEBUI_BRANCH=master

USER root

# Supervisor for running webui + gateway side by side
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor openssl gosu && \
    rm -rf /var/lib/apt/lists/*

# Container marker (webui checks for this)
RUN touch /.within_container

# ── File Browser ──
# Single static binary via the official installer. Run under supervisord so
# it can browse the entire hermes container filesystem. Database + config
# live in /opt/data/filebrowser so they persist across image rebuilds.
# The default admin password is generated on first boot and printed to
# container logs (see filebrowser.md "First Boot").
RUN mkdir -p /opt/data/filebrowser && \
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash && \
    chown -R hermes:hermes /opt/data/filebrowser

# ── Configuration ──
COPY entrypoint.sh /entrypoint.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /entrypoint.sh

# ── Prepare directories for hermes user ──
# Only chown the specific (empty/small) dirs that need it — avoids the
# expensive recursive chown over the entire venv + webui source tree.
ENV WEBUI_INSTALL=/opt/hermes-webui
RUN mkdir -p ${WEBUI_INSTALL} && \
    chown hermes:hermes ${WEBUI_INSTALL} /var/log/supervisor /var/run

# ── Switch to hermes for all heavy I/O (clone + pip install) ──
USER hermes

# ── Hermes Web UI ──
RUN git clone --depth 1 --branch ${WEBUI_BRANCH} ${WEBUI_REPO} ${WEBUI_INSTALL}

# Install webui's deps into the agent venv
RUN . /opt/hermes/.venv/bin/activate && \
    uv pip install --no-cache-dir -r ${WEBUI_INSTALL}/requirements.txt

# ── Back to root for supervisord ──
USER root

# Holographic memory provider: NumPy is optional in upstream but required for
# HRR algebra (probe, reason). Pre-install so the provider is fully functional
# the moment a user runs `hermes memory setup` and selects "holographic".
# The SQLite db lives at $HERMES_HOME/memory_store.db, which is on the
# bind-mounted /opt/data volume, so it persists across redeploys.
RUN . /opt/hermes/.venv/bin/activate && \
    uv pip install --no-cache-dir numpy

ENV PATH="/opt/hermes/.venv/bin:${PATH}"

# WebUI (8787) + Gateway API (8642) + Hermes Dashboard (9119) + File Browser (8080)
EXPOSE 8787 8642 9119 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
