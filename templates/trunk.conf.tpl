[__TRUNK_NAME__]
type = registration
transport = transport-__TRANSPORT__
outbound_auth = __TRUNK_NAME__
server_uri = sip:__SIP_HOST__
client_uri = sip:__SIP_USER__@__SIP_HOST__
contact_user = __SIP_USER__
retry_interval = 60
forbidden_retry_interval = 300
expiration = 300
line = yes
endpoint = __TRUNK_NAME__

[__TRUNK_NAME__]
type = auth
auth_type = userpass
username = __SIP_USER__
password = __SIP_PASSWORD__

[__TRUNK_NAME__]
type = aor
contact = sip:__SIP_HOST__:__SIP_PORT__
qualify_frequency = 30

[__TRUNK_NAME__]
type = endpoint
transport = transport-__TRANSPORT__
context = default
disallow = all
allow = alaw,ulaw
aors = __TRUNK_NAME__
outbound_auth = __TRUNK_NAME__
from_domain = __SIP_HOST__
from_user = __SIP_USER__
direct_media = no
rewrite_contact = yes
rtp_symmetric = yes
force_rport = yes
trust_id_inbound = yes
send_pai = yes

[__TRUNK_NAME__]
type = identify
endpoint = __TRUNK_NAME__
match = __SIP_HOST__
