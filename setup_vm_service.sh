set -e
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip curl ca-certificates
python3 -m venv /opt/teams-agent-vm/.venv
/opt/teams-agent-vm/.venv/bin/pip install --upgrade pip
/opt/teams-agent-vm/.venv/bin/pip install -r /opt/teams-agent-vm/requirements.txt
sudo tee /etc/systemd/system/teams-agent-vm.service >/dev/null <<"EOF"
[Unit]
Description=Teams Agent VM Service
After=network.target

[Service]
Type=simple
User=azureuser
WorkingDirectory=/opt/teams-agent-vm/src
EnvironmentFile=/etc/teams-agent-vm.env
ExecStart=/opt/teams-agent-vm/.venv/bin/python /opt/teams-agent-vm/src/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now teams-agent-vm
echo "IS_ACTIVE=$(systemctl is-active teams-agent-vm || true)"
echo "STATUS_HEAD_START"
systemctl status teams-agent-vm --no-pager | head -n 40
echo "STATUS_HEAD_END"
echo "JOURNAL_START"
journalctl -u teams-agent-vm -n 80 --no-pager
echo "JOURNAL_END"
