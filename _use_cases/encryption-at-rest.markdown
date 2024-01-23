---
name: Encryption At Rest
---

## Why

Apache Kafka&#174; does not directly support any form of encryption for data stored within a broker. This means that the contents
of records sent to Apache Kafka are stored in the clear. Anyone with sufficient privileges, such as a Kafka Administrator
with file system access, is able to read the contents of the records.

This present a challenge for an enterprise using Kafka to distribute confidential data or PII (Personally Identifiable
Information).  Enterprises are often subject to confidential requirements coming from governmental bodies such as
GDPR in the EU or LGPD in Brazil, industry standards such as HIPAA in the health domain or PCI/DSS in the payments domain,
in addition to any in-house security and compliance requirements.

The problem is made more complex if the enterprise has opted to utilise a Cloud Kafka Service as the confidential
data is now residing in the clear on the file systems of the service provider.

| ![image](../assets/encryption-at-rest_problem.png){:width="100%"} |
|:-----------------------------------------------------------------:|
|    *Problem: Plain text records readable by the Kafka Admins*     |

### Isn't TLS sufficient?

TLS encrypts the content _on the wire_.  It means that someone using a network sniffer cannot tap what is being
sent over the wire between the application and the Kafka Broker.  However, once the network packets arrive at the broker,
the packets are decrypted and exist in the clear once again.  This means the confidential records are in the clear in the memory
of the broker and in the clear when the data is written to the file system.

TLS does not change the problem.

### Isn't storage volume encryption an answer?

With storage volume encryption, the contents of the device are encrypted with a key.  This approach provides some mitigations.
If the storage device is stolen or the storage device hijacked and attached to an attacker's computer, the attacker won't have
the encryption key so won't be able to read the data, including the Kafka records.

However, there are shortcomings.  The encrypted storage volume must be mounted to the computers running the Kafka broker. To do
this the  and the encryption keys applied at the operating system level.  Anybody with shell level access to the hosts  is likely
to be able to read the data, including the Kafka confidential records.

Storage volume encryption doesn't really solve the problem.

### Can't the applications encrypt/decrypt the data?

It is possible for producing applications to encrypt data before sending it to Kafka, and for consuming applications to decrypt it
again.  With this approach the brokers never possess the records in the clear and as they don't have encryption keys, they cannot
decrypt it.

So, this approach does offer a solution to the problem but there are disadvantages.

1. Kafka Client libraries don't support encryption themselves.
1. Kafka Client ecosystem is polyglot - it is common to Kafka applications written in many languages (Java, Go, Rust...)
   deployed within a _single organisation_.  Any solution needs to work across all the target languages.
1. There are some encryption libraries for some languages that can be used with the Kafka Clients but these available
   across all languages.

Organisations could write their own encryption code but this is a burden to the application teams. The need for
_interoperability_ between different language encryption implementations - this increases the overheads.  There is also
the problem of key distribution to consider.  Some part of the system needs to push the correct encryption keys out to
the applications and manage tasks such as key rotation.  Finally, cryptography is a specialist area and the consequences
of a design flaw or bug are significant (confidentiality breach).

Having the applications encrypt/decrypt data themselves, whilst technically feasible, is not really a tenable solution
at the scale required for most enterprises.

# Kroxylicious Topic Encryption

The Kroxylicious Topic Encryption feature offers a solution to the problem.  The proxy takes the responsibility
to encrypt and decrypt the messages. In this way, the Kafka Brokers never see the plain text content of
the message thus ensuring confidentiality.  Encryption is introduced into the system without requiring changes to
either applications or the Kafka Cluster.

Within Kroxylicious, the job of encryption and decryption is delegated to a Kroxylicious Filter. The filter intercepts
produce requests from producing applications and encrypts the content, before the produce request is forwarded to the
brokers.  For consuming, the filter intercepts fetch responses and decrypts the contents before the
fetch response is forwarded to the applications.

As the solution is proxy-based, it works regardless of the language the applications is written in.

The solution's foundations rest on industry-standard encryption techniques.

* Envelope Encryption[^1] is employed to efficiently encrypt/decrypt records.
* Integrates with Key Management Services for safe and secure storage of key encryption keys.
  * Plugin for [HashiCorp Vault](https://www.hashicorp.com/)&#174; 
  * Additional KMS implementations are planned.
  * API available to plugin alternatives
* Uses AES-GCM symmetric keys.
* Supports key rotation (new version applied to newly produced records only).
* Records encrypted using previous key-versions remain decryptable.    

[^1]: [NIST SP.-800-57 part 1 revision 5](https://csrc.nist.gov/Projects/Key-Management/Key-Management-Guidelines)

Deployment time configuration at allows the administrator to choose which
encryption keys are to be used to encrypt the records of which topics. Uses cases where some topics
are encrypted and some remain unencrypted are supported.


| ![image](../assets/encryption-at-rest_solution.png){:width="100%"} |
|:------------------------------------------------------------------:|
|           *Kroxylicious Topic Encryption Deployment[^2]*           |

[^2]: The Kafka logo is a trademark of The Apache Software Foundation.  The Vault mark included in the diagram is a trademark of [HashiCorp](https://www.hashicorp.com/).


