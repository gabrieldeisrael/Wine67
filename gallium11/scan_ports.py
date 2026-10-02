import socket

ip = "192.168.3.132"
ports = [22, 2222, 80, 443, 23, 222, 8022]

for port in ports:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((ip, port))
        print(f"Port {port} is OPEN")
        try:
            banner = s.recv(1024)
            print(f"  Banner: {banner}")
        except:
            pass
        s.close()
    except Exception as e:
        print(f"Port {port} closed or filtered: {e}")
