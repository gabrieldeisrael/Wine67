import paramiko
import os

ip = "192.168.3.132"
ssh_dir = os.path.expanduser("~/.ssh")
key_path = os.path.join(ssh_dir, "id_rsa")

users = ["root", "pi", "ubuntu", "debian", "user", "admin", "gallium", "berna"]

for user in users:
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        print(f"Trying key with user {user}...")
        client.connect(ip, username=user, key_filename=key_path, timeout=5)
        print(f"SUCCESS with user {user}!")
        stdin, stdout, stderr = client.exec_command("uname -a; echo $DISPLAY")
        print(stdout.read().decode())
        client.close()
        break
    except Exception as e:
        print(f"Failed for {user}: {e}")
