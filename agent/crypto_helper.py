import json
import os
import logging
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

logger = logging.getLogger(__name__)

class CryptoHelper:
    def __init__(self, key_dir="keys", paired_file="paired_clients.json"):
        self.key_dir = key_dir
        self.paired_file = os.path.join(key_dir, paired_file)
        
        # Ensure directories exist
        os.makedirs(key_dir, exist_ok=True)
        
        self.agent_private_key = self._load_or_generate_key()
        self.paired_clients = self._load_paired_clients()

    def _load_or_generate_key(self):
        """Loads the agent's private key, or generates a new one if missing."""
        key_path = os.path.join(self.key_dir, "agent_private_key.pem")
        if os.path.exists(key_path):
            try:
                with open(key_path, "rb") as f:
                    private_key = serialization.load_pem_private_key(
                        f.read(),
                        password=None
                    )
                logger.info("Successfully loaded agent identity key pair.")
                return private_key
            except Exception as e:
                logger.error(f"Failed to load existing key: {e}. Re-generating...")
        
        # Generate new P-256 key pair
        private_key = ec.generate_private_key(ec.SECP256R1())
        pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        
        try:
            with open(key_path, "wb") as f:
                f.write(pem)
            logger.info("Generated new agent identity key pair.")
        except Exception as e:
            logger.error(f"Failed to save generated private key: {e}")
            
        return private_key

    def get_public_key_pem(self) -> str:
        """Returns the Agent's public key in PEM format."""
        pubkey = self.agent_private_key.public_key()
        pem = pubkey.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        return pem.decode('utf-8')

    def _load_paired_clients(self) -> dict:
        """Loads paired client list from JSON file."""
        if os.path.exists(self.paired_file):
            try:
                with open(self.paired_file, "r") as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Failed to parse paired clients JSON: {e}")
        return {}

    def save_client_key(self, client_id: str, pubkey_pem: str):
        """Registers a new client's public key."""
        self.paired_clients[client_id] = pubkey_pem
        try:
            with open(self.paired_file, "w") as f:
                json.dump(self.paired_clients, f, indent=4)
            logger.info(f"Registered client '{client_id}' successfully.")
        except Exception as e:
            logger.error(f"Failed to save paired client key list: {e}")

    def is_client_paired(self, client_id: str) -> bool:
        """Checks if client_id is in pairing records."""
        return client_id in self.paired_clients

    def get_client_key(self, client_id: str) -> str:
        """Returns client's PEM public key, if registered."""
        return self.paired_clients.get(client_id)

    def verify_signature(self, client_id: str, message: bytes, signature_bytes: bytes) -> bool:
        """
        Verifies ECDSA signature of a message using a client's registered public key.
        Handles both Raw (64-byte) and DER signatures.
        """
        pubkey_pem = self.get_client_key(client_id)
        if not pubkey_pem:
            logger.warning(f"Signature check failed: Client '{client_id}' is not paired.")
            return False

        try:
            # 1. Load PEM public key
            pubkey = serialization.load_pem_public_key(pubkey_pem.encode('utf-8'))
            
            # 2. Convert Raw 64-byte (R || S) Web Crypto signature to DER format
            der_signature = self._raw_to_der(signature_bytes)
            
            # 3. Verify signature
            # Will raise InvalidSignature if verification fails
            pubkey.verify(
                der_signature,
                message,
                ec.ECDSA(hashes.SHA256())
            )
            return True
        except Exception as e:
            logger.error(f"Signature verification failed for client '{client_id}': {e}")
            return False

    def _raw_to_der(self, signature_bytes: bytes) -> bytes:
        """
        Converts 64-byte raw Web Crypto ECDSA signature (R and S concatenation)
        into ASN.1 DER format.
        """
        if len(signature_bytes) != 64:
            # Already DER format (e.g. from openssl or standard libraries)
            return signature_bytes
            
        r = int.from_bytes(signature_bytes[:32], byteorder='big')
        s = int.from_bytes(signature_bytes[32:], byteorder='big')
        return encode_dss_signature(r, s)
