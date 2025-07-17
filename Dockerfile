# Use Docker's modern build syntax to enable mounting secrets
#syntax=docker/dockerfile:1

# Use a modern, slim Python base image
FROM python:3.11-slim-bookworm

# Define build-time arguments for your repository URL and Git host
ARG REPO_URL="git@github.com:your-username/ansible-pull-poc.git"
ARG GIT_HOST="github.com"

# Set environment variables to prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install system dependencies
RUN apt-get update && apt-get install -y \
    sudo \
    git \
    ansible \
    cron \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 2. Create a non-root user to run ansible-pull
RUN useradd --create-home --shell /bin/bash ansible && \
    echo "ansible ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 3. Set up SSH for Git access for the 'ansible' user
RUN mkdir -p /home/ansible/.ssh
RUN chmod 700 /home/ansible/.ssh
RUN ssh-keyscan ${GIT_HOST} >> /home/ansible/.ssh/known_hosts
RUN chown -R ansible:ansible /home/ansible/.ssh

# --- SECTION 4 REMOVED ---
# We no longer need to COPY the private key. We will use a secure build-mount.

# 5. Switch to the 'ansible' user to perform the initial pull
USER ansible
WORKDIR /home/ansible


# Perform an initial ansible-pull using the securely mounted secret
# The --mount flag is enabled by the #syntax line at the top of the file
RUN --mount=type=secret,id=git_ssh_key,uid=1000,gid=1000 \
    ansible-pull -U ${REPO_URL} --private-key /run/secrets/git_ssh_key -i "$(hostname)," --directory /home/ansible/ansible_checkout /home/ansible/ansible_checkout/local.yaml

# 6. Switch back to the 'root' user to set up system-level services (cron)
USER root

# Set up the cron job to use the runtime secret
RUN touch /var/log/ansible-pull.log && chown ansible:ansible /var/log/ansible-pull.log
# MODIFIED: The cron job now points to the secret file mounted by Docker Compose at runtime
RUN echo "*/1 * * * * ansible /usr/bin/ansible-pull -U ${REPO_URL} --private-key /run/secrets/git_ssh_key -i \"\$(hostname),\" --only-if-changed --directory /home/ansible/ansible_checkout >> /var/log/ansible-pull.log 2>&1" > /etc/cron.d/ansible-pull-cron
RUN chmod 0644 /etc/cron.d/ansible-pull-cron

# 7. Set the final command to run cron and tail the log file
CMD ["sh", "-c", "cron && tail -f /var/log/ansible-pull.log"]
