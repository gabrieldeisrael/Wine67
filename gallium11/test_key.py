import paramiko
import sys
import os

ip = "192.168.3.132"
users = ["root", "pi", "ubuntu", "debian", "user", "admin", "gallium", "berna"]
key_path = os.path.expanduser("~/.ssh/id_rsa")

for user in users:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        print(f"Trying key for user {user}...", end="", flush=True)
        client.connect(ip, username=user, key_filename=key_path, timeout=3)
        print(" SUCCESS!")
        stdin, stdout, stderr = client.exec_command("uname -a")
        print(stdout.read().decode())
        client.close()
        sys.exit(0)
    except Exception as e:
        print(f" failed ({e})")
