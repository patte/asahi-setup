#!/usr/bin/env bash
# Installs just enough to run the playbook, then hands off to run.sh.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Installing Ansible"
# ansible (not just ansible-core) for the community.general collection, which
# provides the copr and dconf modules.
# python3-libdnf5 is what the ansible.builtin.dnf5 module binds to on F41+.
sudo dnf install -y ansible python3-libdnf5 git

echo
echo "==> Ansible ready:"
ansible --version | head -1

echo
echo "Next:"
echo "  ./run.sh              # provision everything except the kernel"
echo "  ./run.sh fairydust    # then, deliberately, the kernel"
