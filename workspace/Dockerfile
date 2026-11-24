# The learner workspace for the FHIR analytics codelab.
#
# It holds Node and Observable Framework with a warm npm cache, the dashboard
# project, the lab commands, a Postgres client, Python for the data generator,
# and code-server, which is VS Code served to a browser.

FROM node:20-bookworm

ARG CODE_SERVER_VERSION=4.145.2

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git inotify-tools jq less nano vim \
      postgresql-client python3 python3-requests \
 && curl -fsSL -o /tmp/code-server.deb \
      "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb" \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/code-server.deb \
 && rm -rf /tmp/code-server.deb /var/lib/apt/lists/*

# One unprivileged account with uid 1000. The Node image has one named node
# on that uid, which is removed first.
RUN (id node >/dev/null 2>&1 && userdel -r node || true) \
 && useradd --create-home --uid 1000 --shell /bin/bash learner \
 && chmod 755 /home/learner

# The lab files. pipeline/ is filled by two bind mounts at run time. The
# pristine copy kept here is what reset-views restores.
COPY --chown=learner:learner lab /home/learner/lab
COPY --chown=learner:learner pristine /opt/codelab/pristine

USER learner
WORKDIR /home/learner/lab/dashboard
ENV CODELAB_DIR=/home/learner/lab

# Install the dashboard's packages now, so a learner never waits for npm, then
# build the site once from the sample data, so the Dashboard tab shows
# something before the first pipeline run.
RUN npm install --no-audit --no-fund \
 && LAB_SAMPLE=1 npx observable build


COPY --chown=learner:learner ide/settings.json /home/learner/.local/share/code-server/User/settings.json
COPY --chown=learner:learner ide/bashrc        /home/learner/.bashrc.codelab
RUN echo '. ~/.bashrc.codelab' >> /home/learner/.bashrc

USER root
COPY ide/codelab-guide /opt/codelab/guide-ext
# A VSIX package is a zip file.
RUN python3 -c "import shutil; shutil.make_archive('/opt/codelab/codelab-guide', 'zip', '/opt/codelab/guide-ext')" \
 && mv /opt/codelab/codelab-guide.zip /opt/codelab/codelab-guide.vsix \
 && chmod 644 /opt/codelab/codelab-guide.vsix \
 && mkdir -p /opt/codelab/guide
USER learner
RUN code-server --install-extension /opt/codelab/codelab-guide.vsix

COPY --chmod=755 bin/ /usr/local/bin/

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/workspace-entrypoint"]
