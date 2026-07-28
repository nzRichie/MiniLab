#!/bin/bash
# DNS reflector starter config (honest infrastructure, pre-armed). An ordinary
# authoritative server. It serves one synthetic name, amplify.lab, whose TXT
# record is deliberately large, plus the real TXT record sets of three well-known
# domains (google.com, spotify.com, amazon.com) captured with dig on 2026-07-28.
# The real sets let a learner compare which name makes the better reflector: the
# more TXT strings a name carries, the larger the reply a small query draws back.
# The server is not misconfigured in any exotic way; it answers the query it is
# asked, which is all a reflector has to do. The attacker abuses that by asking
# with a forged source.
set -e

ip address add 102.1.0.53/24 dev 102-S1 2>/dev/null || true
ip link set 102-S1 up
ip route add default via 102.1.0.1 2>/dev/null || true

# One oversized synthetic TXT record. 250 bytes of payload keeps the whole reply
# inside a single 512-byte UDP DNS message (no EDNS, no truncation), so a plain
# query gets the full amplified answer back. This is the record the walkthrough
# and the reflect tool query by default.
PAYLOAD="$(printf 'A%.0s' $(seq 1 250))"
cat > /etc/dnsmasq-lab.conf <<EOF
# Reflector for the lab. Authoritative only; no recursion, no upstream, no local
# hosts file. Serves amplify.lab plus three real domains' TXT sets (appended below).
port=53
no-resolv
no-hosts
log-queries
# Allow EDNS0 replies up to 4096 bytes over UDP. A plain 512-byte query still caps
# at 512; a query that advertises a larger buffer draws the bigger real answers,
# up to this ceiling. amazon.com's set exceeds 4096, so its reply truncates here
# (the TC flag is set) and the full answer only arrives over TCP.
edns-packet-max=4096
txt-record=amplify.lab,"$PAYLOAD"
EOF

# The real TXT record sets, captured with `dig TXT <domain>` on 2026-07-28. One
# txt-record line per TXT resource record, verbatim (records sorted for a stable
# snapshot). dnsmasq returns every line that shares a name as a separate RR, so a
# query for the name draws the whole set back. A quoted heredoc keeps the data
# literal: none of it is shell-expanded.
cat >> /etc/dnsmasq-lab.conf <<'REAL'
# --- google.com: real TXT record set, snapshot 2026-07-28 ---
txt-record=google.com,apple-domain-verification=30afIBcvSuDV2PLX
txt-record=google.com,cisco-ci-domain-verification=47c38bc8c4b74b7233e9053220c1bbe76bcc1cd33c7acf7acd36cd6a5332004b
txt-record=google.com,docusign=05958488-4752-4ef2-95eb-aa7ba8a3bd0e
txt-record=google.com,docusign=1b0a6754-49b1-4db5-8540-d2c12664b289
txt-record=google.com,facebook-domain-verification=22rm551cu4k0ab0bxsw536tlds4h95
txt-record=google.com,globalsign-smime-dv=CDYX+XFHUw2wml6/Gb8+59BsH31KzUr6c1l2BPvqKX8=
txt-record=google.com,google-site-verification=4ibFUgB-wXLQ_S7vsXVomSTVamuOXBiVAzpR5IZ87D0
txt-record=google.com,google-site-verification=TV9-DBe4R80X4v0M4U_bd_J9cpOJM0nikft0jAgjmsQ
txt-record=google.com,google-site-verification=wD8N7i1JTNTkezJ49swvWW48f8_9xveREV4oB-0Hf5o
txt-record=google.com,MS=E4A68B9AB2BB9670BCE15412F62916164C0B20BB
txt-record=google.com,onetrust-domain-verification=0d477fe608074e6f9c12bca7826035cc
txt-record=google.com,onetrust-domain-verification=6d685f1d41a94696ad7ef771f68993e0
txt-record=google.com,v=spf1 include:_spf.google.com ~all
txt-record=google.com,work-accounts-domain-verification=Tcj6JjIMZOw2KsSEw2Nt2rLae89tN6
txt-record=google.com,Z29vZ2xl
# --- spotify.com: real TXT record set, snapshot 2026-07-28 ---
txt-record=spotify.com,anthropic-domain-verification-mqtmtz=BSac9xfxvigNt4Ralt2KPkt1V
txt-record=spotify.com,_anz60jg9dhixqlmcv20ntnooz9m0k8x
txt-record=spotify.com,apple-domain-verification=Dxae2sKJD2O5TKGK
txt-record=spotify.com,atlassian-domain-verification=1My5WsxLluUY8uIjgbLs4MY3ySFp32k9aYNW2IR4ihM64k58CxpFnB5R9SEiJAnR
txt-record=spotify.com,atlassian-sending-domain-verification=d90f2e0c-fa57-43b6-910f-065cc4d6a0e3
txt-record=spotify.com,cloudflare_dashboard_sso=19cd522a4fc20281209f03663d34ee76
txt-record=spotify.com,cursor-domain-verification-985xgr=7ROYkkLIfunrK2GtW0spMGDNw
txt-record=spotify.com,docker-verification=82f3553a-fb50-4d4e-9607-8a8079ee354f
txt-record=spotify.com,facebook-domain-verification=qyrvuca7h4s7wevhzbprtt3tdyyhf1
txt-record=spotify.com,facebook-domain-verification=wtgn9pdvjdhs21j9gz6knsnpkafvs5
txt-record=spotify.com,google-site-verification=0wmxUE7T2OWPhtwjco6oCyqqbYgtosjQdywAr4G4kU0
txt-record=spotify.com,google-site-verification=buTP-BbGUoP8lPntqskvSbeS68M4PDoIFkiUtQEA5n8
txt-record=spotify.com,google-site-verification=ehIHBRyAOKdOfUyw_ONXT0TMuUsdk1gDGSYfk8YhRgw
txt-record=spotify.com,google-site-verification=ESiNWockZgSgTPSsrsAdMX9afsj2-_8504nQ0qIHkDA
txt-record=spotify.com,google-site-verification=uD4f4k01lFWX3qwVbqnVaJg8atpKgAgc-_RYcyT3ofU
txt-record=spotify.com,have-i-been-pwned-verification=33b7ae688099ee8cca63259b769a0ea8
txt-record=spotify.com,jamf-site-verification=1kKxrm0glhWvrA0YiABH_w
txt-record=spotify.com,liveramp-site-verification=IAXPTLlWofr4aaKtwVqirrHvOqUMiXnaMW8WMmuz1v0
txt-record=spotify.com,loom-site-verification=3ee9ca8c2df34d08abbb7be5185bc768
txt-record=spotify.com,MS=ms38184034
txt-record=spotify.com,notion-domain-verification=AqUDuql68X5rQ1qLwho6huUjf4QteXZlyvTIKS1txnq
txt-record=spotify.com,onetrust-domain-verification=508849d40e2b4b8fba2b7eaf84f1bddc
txt-record=spotify.com,openai-domain-verification=dv-VNYvLsJIttFvRz7ymxFgjrPC
txt-record=spotify.com,parallels-domain-verification=7bb3a358f26f4e23a5077648266570c873182a57d6d44e47a55ef6cf72cdb470
txt-record=spotify.com,reachdesk-verification=v0DuUrKxORfyqxIOMkJm57GlQtvaAv0watqt7x7ylMN21LAHqR6dEhUpSxOp7DCh
txt-record=spotify.com,status-page-domain-verification=wq4jns7ydgbb
txt-record=spotify.com,tiktok-developers-site-verification=98xFqMKsOJ51nNJpUCGPGbo7m17gtf7f
txt-record=spotify.com,tiktok-developers-site-verification=pZNawVY3o5Ma80MRCC6Fref1NiLzuEVU
txt-record=spotify.com,tiktok-developers-site-verification=ttGXJxgq1HQKquomgiljzFq53uoLHcUC
txt-record=spotify.com,vmware-cloud-verification-dab4c35d-1819-4431-add3-d3c382ee32bc
txt-record=spotify.com,v=spf1 ip4:80.76.146.172 ip4:80.76.146.173 include:_spf.google.com include:servers.mcsv.net include:_spf.salesforce.com include:_spf.netigate.se include:21894833.spf06.hubspotemail.net ~all
txt-record=spotify.com,windsurf-verification=LRBAV_kH3G5aleY1GIc1jMUg_8iBpigIm2qYF00bRps=
txt-record=spotify.com,wiz-domain-verification=370862886b04dfa626d54d2c4cc955174c6f3164a104a85d725ae5ece72ea3ef
txt-record=spotify.com,yahoo-verification-key=bdudmGyddArwRiVafgItrfYq8nrhd5vzNZ7Ik/G0ILM=
txt-record=spotify.com,zapier-domain-verification-challenge=db8a0b98-bb6a-4f84-a699-344dc23fef3b
# --- amazon.com: real TXT record set, snapshot 2026-07-28 ---
txt-record=amazon.com,00DcX000002xu6h=1TBcX00000000Xt
txt-record=amazon.com,apple-domain-verification=4wbNaeWvAH0pU1yi
txt-record=amazon.com,apple-domain-verification=dVkKZnu17XS0EN2X
txt-record=amazon.com,apple-domain-verification=_j3fIZD8uuYetbG64YKTEpz-8mwyvYrLRqM5CoVZVTk
txt-record=amazon.com,atlassian-domain-verification=ZT4AapXgobCpXIWoNcd7gtMjZyOUdr4EDFMnFUWrqqqgdaQVbDvoGpRaIwj/tgPH
txt-record=amazon.com,autodesk-domain-verification=dmryiygGOGBJFJFVo5Bl
txt-record=amazon.com,box-domain-verification=ffea95cd0e0d61c302198367155b07e74fd534fa1d867662dc9bf9969b6f535d
txt-record=amazon.com,brevo-code:9be7f7c39958d253a31de6593fa831bc
txt-record=amazon.com,canva-site-verification=Hksh9WEUPWP13_SEU1mPMA
txt-record=amazon.com,canva-site-verification=WhUvTbfe6tUQWmIXnQifGA
txt-record=amazon.com,cisco-ci-domain-verification=1b256bd11daa486ba2fa405d2d5de70f75feb6757dd8993ca8de685a7dfea1df
txt-record=amazon.com,dell-technologies-domain-verification=amazon.com_2dc4b285-482d-4948-bf92-16e698f2cab9_1738858526
txt-record=amazon.com,docker-verification=1779f74e-699a-4d8b-acdc-ce242d73559f
txt-record=amazon.com,facebook-domain-verification=d9u57u52gylohx845ogo1axzpywpmq
txt-record=amazon.com,google-site-verification=14WGW2MdNMxchG8PlinF7LgqqE0OwwHqOq0HKhb7rDQ
txt-record=amazon.com,google-site-verification=D0RwRb_QApkpApKTFaFlRwbm_yrkey0uokKw0wQUIdk
txt-record=amazon.com,google-site-verification=G_-mXb0ZYjjGkQVGjpOOB2deSOaVdxVj4i4vozJTREs
txt-record=amazon.com,google-site-verification=NV91qEfNgqDZOPzwlhXE-KtDUfCBSNgAsdxaFebyh80
txt-record=amazon.com,liveramp-site-verification=jZJKgMEQ_1mdjMhKj02iqNACZ-NJHRWhCEQdQ_OuCMo
txt-record=amazon.com,lucidlink-verification=QG752KJ3CMZAZTZ3ERMX1AXMCG
txt-record=amazon.com,MS=4B600B22799EB2CAC0D8FF0A3A3CAECA5EE2BF3A
txt-record=amazon.com,neat-pulse-domain-verification-QgvLWLN=f37f2998-0bb3-493b-a3aa-c4ff8f3dce08
txt-record=amazon.com,pardot326621=b26a7b44d7c73d119ef9dfd1a24d93c77d583ac50ba4ecedd899a9134734403b
txt-record=amazon.com,pendo-domain-verification=ecbe1a51-954d-4202-ab86-d15e04b96769
txt-record=amazon.com,pstk-verification-a938892542ffacd51af9339e4755dc1a
txt-record=amazon.com,sending_domain1003771=199bc63a54ace5d8d5c5d08286af86d7049b4afacb5ef7decd6b22cf9e8d5efb
txt-record=amazon.com,sending_domain1003771=f1303d8ee3b86e39db2703b11feb83e1e8b712a9ffc64c3d56505192e5b3bf4f
txt-record=amazon.com,sending_domain1014172=003846595520e80ec84e8cc47c07e3a71afb855fc743bb92cdec93f88c7a4029
txt-record=amazon.com,sending_domain197572=555e96ed2e576ced81c89f7001740cb72f9c66aeb136d0d05734aad625766bc1
txt-record=amazon.com,sending_domain229492=341509a116ea4311fcb2e489303bf09a139b10ce9b90e5029d2677055cb4dc89
txt-record=amazon.com,sending_domain229492=7cde83fbc5246557c64d9d9ba79f0d11f7ba9eb6127f60451a9aa6f8dead4381
txt-record=amazon.com,sending_domain608861=81b0d52095dae60d604e7cbea5e58e1d842f7d950d6673a43feae339b664ca31
txt-record=amazon.com,sending_domain608861=d33a88e8540c33a1217138cf8a25879734bd35673bb7cfbd639f95c550b33ec4
txt-record=amazon.com,sending_domain949422=43d714838567583460e7720e6049505edb8e25c1ef4321419d41bc5255db7ba5
txt-record=amazon.com,sending_domain949422=99a7b44052aefc4dec2abf56189160824664d2fdac00ca962f4455be62b51d56
txt-record=amazon.com,spf2.0/pra include:spf1.amazon.com include:spf2.amazon.com include:amazonses.com -all
txt-record=amazon.com,stripe-verification=1D421397AAEC571CCBD9F25DDC90F00EDEBC3E74F4047270EC9A13B784579E34
txt-record=amazon.com,stripe-verification=26EFABF97D624D7F4F3C062366A04C4B1399841F23F275DD81E58D00A981979C
txt-record=amazon.com,stripe-verification=35A865E5A20C09CD0288F87ACA29DE73FF8A704D21F7310A5AAFF4CB63062E81
txt-record=amazon.com,stripe-verification=45f746e3b195198f419af3f685fdf217532ce552b4b47070b3caefe325559a67
txt-record=amazon.com,stripe-verification=65883709F0B36AB2B73FFC870338AE9F817315DDBB1CAB28910F074F4A8DE1EC
txt-record=amazon.com,stripe-verification=6a5d107aa37465eac2101bb1c725b02072689a4fa7bd38b455970baac4979a17
txt-record=amazon.com,stripe-verification=76924B623B7105057C67D4F5EAE19F65EE8BD92635581BCACA2CCACA4D38FE1B
txt-record=amazon.com,stripe-verification=79C640ED20153B836A623F16A3DCF65E2072948FB80C42D19300514DADF94EC5
txt-record=amazon.com,stripe-verification=8E217BE0FF12B50596BD78EEA3F81E62C6C7A2AC78FBD46DAD95B7D21BA2F8BF
txt-record=amazon.com,stripe-verification=a27edc0da55836ea6bb7eac592bf2ca8e246eb652608d54493119df7df005afc
txt-record=amazon.com,stripe-verification=a5c01aa4d732f4b93154d67983d77982ef1a2db73fecfd4bcd64e224d3ab4075
txt-record=amazon.com,stripe-verification=B0AD8DC1918B8A717E5B6A29C2E04594A9872AB05F8DA24CB762BBA0A0487BC6
txt-record=amazon.com,stripe-verification=C7ABA7B41F5AC26E3C397015A34CD46ACD2130DC8DAAFA7F59AAEFEDBC3FA517
txt-record=amazon.com,TS1760027
txt-record=amazon.com,uber-domain-verification=01e9f567-7b84-45dd-9326-53992a028b40
txt-record=amazon.com,uber-domain-verification=0ddb4c64-175c-4e7a-8a7a-f552034222e8
txt-record=amazon.com,uber-domain-verification=5f5cc242-4dbe-4871-b726-bbbe085ff053
txt-record=amazon.com,uber-domain-verification=72ffdffb-d431-452c-932e-cd1030d1eb46
txt-record=amazon.com,uber-domain-verification=7a35217f-6956-41a0-be5c-a28ea2646964
txt-record=amazon.com,vizcom-domain-verification-Otrns5=NtkDXOBddZZnm9ETuwyrltTdl
txt-record=amazon.com,v=spf1 include:spf1.amazon.com include:spf2.amazon.com include:amazonses.com -all
txt-record=amazon.com,wrike-verification=MzI3NzM2ODo2NDk5MjE4NjQ2MWJmOTEwMGMxM2MzNzJmNWJlY2U5ZDU4MmVlNzQ2NWU4MTY5OWJjMjlmYjQ4Mjc5M2JiMzky
txt-record=amazon.com,ZOOM_verify_6OUC1znUonKMCoyMMGyFfX
txt-record=amazon.com,ZOOM_verify_ARI4AiKALCcjulAUZNwR8S
txt-record=amazon.com,ZZQHY11TNIE58IL4LBKKT51FQ59LYM243WZU3MJM5OLQMLVBN0TR564SD8SXZU2G
REAL

# Restart cleanly so a reset always comes up with a fresh listener.
pkill -x dnsmasq 2>/dev/null || true
for _ in $(seq 1 25); do pgrep -x dnsmasq >/dev/null 2>&1 || break; sleep 0.2; done
dnsmasq -C /etc/dnsmasq-lab.conf || { echo "dnsmasq failed to start" >&2; exit 1; }
echo "dns reflector up at 102.1.0.53 (amplify.lab + real google/spotify/amazon TXT sets)"
