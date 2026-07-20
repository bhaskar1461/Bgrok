import http.server
import ssl
import os
import socket
import ipaddress
from datetime import datetime, timedelta, timezone
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

def get_local_ip():
    """Gets the active local IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Doesn't even need to be reachable, just triggers OS interface lookup
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

def generate_self_signed_cert(cert_path="cert.pem", key_path="key.pem"):
    """Generates a self-signed SSL certificate valid for localhost and the active LAN IP."""
    if os.path.exists(cert_path) and os.path.exists(key_path):
        return
        
    print("Generating self-signed SSL certificate to enable mobile browser secure context...")
    
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )
    
    local_ip = get_local_ip()
    
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, u"US"),
        x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, u"California"),
        x509.NameAttribute(NameOID.LOCALITY_NAME, u"San Francisco"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, u"bgrok"),
        x509.NameAttribute(NameOID.COMMON_NAME, local_ip),
    ])
    
    cert = x509.CertificateBuilder().subject_name(
        subject
    ).issuer_name(
        issuer
    ).public_key(
        private_key.public_key()
    ).serial_number(
        x509.random_serial_number()
    ).not_valid_before(
        datetime.now(timezone.utc) - timedelta(days=1)
    ).not_valid_after(
        datetime.now(timezone.utc) + timedelta(days=365)
    ).add_extension(
        x509.SubjectAlternativeName([
            x509.DNSName(u"localhost"),
            x509.IPAddress(ipaddress.ip_address(local_ip)),
            x509.IPAddress(ipaddress.ip_address("127.0.0.1"))
        ]),
        critical=False,
    ).sign(private_key, hashes.SHA256())
    
    # Write certificate PEM
    with open(cert_path, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
        
    # Write private key PEM
    with open(key_path, "wb") as f:
        f.write(private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        ))
        
    print("SSL certificate generated successfully.")

def run():
    cert_path = "cert.pem"
    key_path = "key.pem"
    generate_self_signed_cert(cert_path, key_path)
    
    local_ip = get_local_ip()
    server_address = ('0.0.0.0', 8000)
    
    # Serve files from the client/ subdirectory so the page loads at root URL
    client_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "client")
    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(*args, directory=client_dir, **kwargs)
    
    httpd = http.server.HTTPServer(server_address, handler)
    
    # Setup SSL Context
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=cert_path, keyfile=key_path)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    
    print("==================================================")
    print("      bgrok Secure HTTPS Client Server Boot      ")
    print("==================================================")
    print(f"Listening on local loopback : https://localhost:8000")
    print(f"Listening on local network  : https://{local_ip}:8000")
    print("==================================================")
    print("Open the link on your phone. Accept the SSL warning.")
    print("==================================================")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping HTTPS server...")

if __name__ == "__main__":
    run()
