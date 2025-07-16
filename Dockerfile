# Use a modern, slim Python base image
FROM python:3.11-slim-bookworm

# Define build-time arguments for your repository URL and Git host
# You can override these during the build process
ARG REPO_URL="git@github.com:your-username/ansible-pull-poc.git"
ARG GIT_HOST="github.com"

# Set environment variables to prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install system dependencies
# We need sudo, git, ansible, cron for scheduling, and openssh-client for keyscan
RUN apt-get update && apt-get install -y \
    sudo \
    git \
    ansible \
    cron \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 2. Create a non-root user to run ansible-pull
# And grant passwordless sudo privileges for simplicity in this POC environment
RUN useradd --create-home --shell /bin/bash ansible && \
    echo "ansible ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Switch to the new user for user-specific setup
USER ansible
WORKDIR /home/ansible

# 3. Set up SSH for Git access
# Create the.ssh directory and add the Git host to known_hosts.
# This avoids interactive "Are you sure you want to continue connecting?" prompts.
RUN mkdir -p /home/ansible/.ssh && \
    chmod 700 /home/ansible/.ssh && \
    ssh-keyscan ${GIT_HOST} >> /home/ansible/.ssh/known_hosts

# 4. Securely copy the private key from a build secret
# This is the most secure method to handle keys during a build.
# The key is only available during this RUN command and is not stored in any image layer.
RUN --mount=type=secret,id=git_ssh_key \
    cp /run/secrets/git_ssh_key /home/ansible/.ssh/id_rsa_ansible_pull && \
    chmod 600 /home/ansible/.ssh/id_rsa_ansible_pull

# 5. Perform an initial ansible-pull during the build
# This validates that the repository access and playbook are working correctly.
# It also pre-populates the checkout directory.
RUN ansible-pull \
    -U ${REPO_URL} \
    --private-key /home/ansible/.ssh/id_rsa_ansible_pull \
    -i "$(hostname)," \
    --directory /home/ansible/ansible_checkout

# Switch back to the root user to set up system-level services (cron)
USER root

# 6. Set up the cron job for periodic pulls
# Create the log file and the cron definition file that will execute ansible-pull.
RUN touch /var/log/ansible-pull.log && \
    chown ansible:ansible /var/log/ansible-pull.log && \
    echo "*/1 * * * * ansible /usr/bin/ansible-pull -U ${REPO_URL} --private-key /home/ansible/.ssh/id_rsa_ansible_pull -i \"\$(hostname),\" --only-if-changed --directory /home/ansible/ansible_checkout >> /var/log/ansible-pull.log 2>&1" > /etc/cron.d/ansible-pull-cron && \
    chmod 0644 /etc/cron.d/ansible-pull-cron

# 7. Set the final command to run cron and tail the log file
# This starts the cron daemon and then follows the log file,
# allowing you to see the output of the cron job in real-time using 'docker logs'.
CMD ["sh", "-c", "cron && tail -f /var/log/ansible-pull.log"]
