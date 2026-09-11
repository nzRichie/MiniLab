#!/usr/bin/env bash
# Shared definitions for the scanning practice range.
# Sourced by generate/spawn/status/score/reveal/shell/regenerate/teardown/selftest.
# No side effects.
#
# This file holds everything about the range that does NOT change between spawns:
# the AS number, the container naming, the tier ladder, the shape set, the
# container budget, the scoring weights and the par times. It holds no addresses
# at all. Every address, every host, every service and every behaviour flag is
# drawn from the seed by generate.sh and written to state/topology.env, which
# every other script sources after this one.
#
# That split is the range's central invariant: lib.sh is what an author edits,
# topology.env is what a seed produces, and no script outside generate.sh may
# derive an address, a port or a version.

AS=116
DC=RANGE
LAYER=L4

# Lab root (parent of scripts/), resolved regardless of the caller's CWD.
LAB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"

# Generated per spawn, gitignored, and shipped in neither release profile. It
# sits at the LAB ROOT rather than under scripts/ because make-release.sh copies
# named directories (scripts/, default_config/, image/) instead of globbing the
# lab, so a state/ here is excluded from both profiles without either release
# script needing to know this lab exists.
STATE_DIR="$LAB_DIR/state"
TOPO_ENV="$STATE_DIR/topology.env"
FINDINGS_COPY="$STATE_DIR/findings.txt"     # score.sh's copy of the learner's file
ATTEMPTS_LOG="$STATE_DIR/attempts.log"
SCORED_MARKER="$STATE_DIR/scored"           # written by score.sh, cleared by generate.sh

# Where the learner's findings live inside the attacker container. The `report`
# command in the image appends to it; score.sh copies it out with `docker cp`.
FINDINGS_PATH="/root/findings.txt"

# Emit `NAME='value'` for a file a shell will source, closing, escaping and
# reopening the quoting around any single quote in the value. spawn.sh writes
# range.env and one profile.env per service this way. One organisation's team is
# "the department's technicians", and interpolating that into a single-quoted
# heredoc line ended the string early: profile.env stopped parsing at that line,
# the profile script read no ports and no parameters, and the spawn died on the
# first host. It took 64 of 300 drawn ranges with it, because the organisation is
# drawn from a table of five, so a fifth of all ranges were unspawnable.
kv() { printf "%s='%s'\n" "$1" "${2//\'/\'\\\'\'}"; }

# ---------------------------------------------------------------------------
# The tier ladder.
#
# Tier sets the shape, the sizes, and how much the learner is told at the start.
# The third of those is what makes the tiers different exercises rather than the
# same exercise at different lengths: at easy the one subnet is handed over and
# scores nothing, at normal the enclosing /16 is given and which /24s exist
# inside it is the work, and at hard nothing is given at all, so the learner
# reads their own interface for the second octet and builds the map from there.
TIERS=(easy normal hard)

# Difficulty and variety are two separate dials, and tying them together is what
# made the easy tier the same range every time. Content (hosts, segments, dead
# ranges, how much is running) now rises only gently across the tiers; what the
# learner is TOLD carries nearly all of the difficulty. So easy is a busy network
# that comes with a map, rather than a bare /24 with four hosts on it.
declare -A TIER_SHAPES=(
    [easy]="flat fan"
    [normal]="fan chain"
    [hard]="chain mixed"
)

# Live segments (dead ranges are counted separately, below).
declare -A TIER_SEG_MIN=( [easy]=1 [normal]=2 [hard]=3 )
declare -A TIER_SEG_MAX=( [easy]=2 [normal]=3 [hard]=3 )

# Total hosts across every live segment.
declare -A TIER_HOST_MIN=( [easy]=6 [normal]=6 [hard]=7 )
declare -A TIER_HOST_MAX=( [easy]=7 [normal]=8 [hard]=9 )

# Subnets that appear in a router's table and hold no host. Sweeping one buys
# nothing and costs real time, which is what makes reading an ICMP unreachable a
# skill rather than a curiosity.
declare -A TIER_DEAD_MIN=( [easy]=0 [normal]=1 [hard]=1 )
declare -A TIER_DEAD_MAX=( [easy]=1 [normal]=1 [hard]=2 )

# Par times, in seconds. Hand-set, and revised once a perfect player's runtime is
# known. score.sh reports elapsed against par and neither gates nor scales the
# score by it: par is there so a learner can see whether they are working at the
# pace the range was built for. Easy rose from 600 with the host count and the
# chain, and all three rose again with the service palette: seventeen profiles
# with six of them on UDP means a survey that scans TCP alone is not a survey,
# and a UDP sweep waits on an ICMP rate limit it cannot hurry.
declare -A TIER_PAR=( [easy]=1200 [normal]=1800 [hard]=2700 )

# ---------------------------------------------------------------------------
# The opening: what the learner is handed at spawn.
#
# One kind is drawn per range from the tier's list, so two spawns at one tier
# differ in the first move as well as in the map. Every kind on a tier's list is
# the same amount of work; the kind decides where that work starts, not how much
# of it there is.
#
#   segs         every live segment's /24, handed over. Scores nothing, because
#                nothing was found.
#   candidates   every live segment's /24 plus two that do not exist, unordered.
#                Scores in full: which of them are real is the work.
#   count        the enclosing /16 and how many live segments are in it. Scores
#                in full, and the count is what tells a learner when to stop.
#   prefix       the enclosing /16 and nothing else.
#   dns          the address of the host that is authoritative for the zone.
#                Only drawn on a range that has one.
#   nothing      the attacker's own address and default gateway, already on its
#                own interface, and not one thing more.
declare -A TIER_OPENINGS=(
    [easy]="segs candidates count"
    [normal]="prefix candidates dns"
    [hard]="nothing nothing count"
)

# ---------------------------------------------------------------------------
# The shape set.
#
# The seed draws the graph before it draws anything else: a range whose shape is
# fixed and whose addresses move is the same exercise twice with different
# digits. Shapes are drawn from a named set rather than as a free random graph so
# that the generator stays testable and every range is legible when reveal.sh
# prints it.
#
#   flat   attacker -- r1 -- one segment
#   fan    attacker -- r1 -- two or three segments, each on its own bridge
#   chain  attacker -- r1 -- r2 [-- r3], one segment hanging off each
#   mixed  attacker -- r1, which fans to a segment and to r2, which fans to two
#
# Two properties of the plumbing keep this cheap. One OVS container holds a
# bridge per segment and they do not forward between each other, so N segments
# cost N bridges and no extra container. Inter-router links are point-to-point
# veths, the same primitive the attacker's own link uses, so depth costs one
# container per router and no bridge at all.
SHAPES=(flat fan chain mixed)

# One attacker, one switch, up to three routers, up to nine hosts, and at three
# layers and deeper the vault. The generator enforces this and fails rather than
# drawing a range that will not boot on a laptop.
MAX_CONTAINERS=15
MAX_ROUTERS=3
MAX_HOSTS=9

# ---------------------------------------------------------------------------
# The chain: how a learner gets in, and how deep in they can get.
#
# The survey half of this range asks what is out there. The chain asks what one
# of those services is good for, and it is the half that ends on a win rather
# than on a number. It is scored by milestone, so depth reached pays even when
# the last door does not open.
#
# Depth is set by the tier and then by the shape, so a bigger network is a longer
# game rather than the same game with more addresses in it:
#
#   2 layers  every easy range: telnet foothold, and the flag on that host.
#   3 layers  normal, and hard on a chain shape: foothold, then the vault, which
#             sits behind an ACL and is reachable from the foothold host alone.
#   4 layers  hard on a mixed shape: foothold, an SSH host the foothold's key
#             opens, and the vault behind that.
declare -A TIER_DEPTH=( [easy]=2 [normal]=3 [hard]=3 )
DEPTH_MIXED=4          # the one shape that adds a layer to its tier's depth

# The milestones, in order. Each is a token the learner reads off a machine they
# reached and submits with `report flag`. A range holds the first DEPTH-1 of
# these plus `flag`, so which ones exist follows from the depth above.
CHAIN_MILESTONES=(foothold pivot vault)

# Milestone weights, in raw points before the total is scaled to 100.
#
# Staged rather than all-or-nothing, because a single terminal prize makes scores
# bimodal and the range punishing: a learner who cracked the foothold and could
# not open the vault would score exactly what a learner who never logged in
# anywhere scored. Deeper shapes hold more of these, so the chain is worth more
# on a bigger range without a separate rule saying so.
declare -A W_MILESTONE=( [foothold]=6 [pivot]=10 [vault]=14 )
W_FLAG=20

# ---------------------------------------------------------------------------
# Assets and unlocks: how the way in is drawn rather than written.
#
# An ASSET is something a learner comes to possess: the name of a shared account,
# its password, the passphrase on a private key, the name of a file that is
# readable by name and not by listing. An UNLOCK is an action against one service
# that yields one asset, and some unlocks need an asset of their own first.
#
# The generator picks the producers for each asset the chain needs, forces those
# profiles onto hosts, and draws more producers than the chain strictly requires
# as the tier rises. That is what makes the way in a graph rather than a
# corridor: at hard there are three ways to learn the account name and two ways
# to learn its password, and which of them a learner finds first is theirs.
#
# The producer lists are ordered by nothing: the draw shuffles them.
declare -A ASSET_PRODUCERS=(
    [account]="leaked-account smtp-vrfy snmp-public hidden-path"
    [password]="weak-telnet-pass tftp-file redis-open"
    [filename]="rsync-module mqtt-open hidden-path"
    [passphrase]="leaked-passphrase redis-open rsync-module mqtt-open"
)

# The service each unlock is performed against. Placing a producer means forcing
# this profile onto a host.
declare -A UNLOCK_PROFILE=(
    [leaked-account]=ftp    [smtp-vrfy]=smtp   [snmp-public]=snmp
    [hidden-path]=http      [weak-telnet-pass]=telnet
    [tftp-file]=tftp        [redis-open]=redis [rsync-module]=rsync
    [mqtt-open]=mqtt        [leaked-passphrase]=ftp
)

# The asset an unlock needs before it yields anything. An unlock with no entry
# here needs nothing but a scan, which is what makes it a way into the graph
# rather than a step inside it.
declare -A UNLOCK_REQUIRES=(
    [weak-telnet-pass]="account"
    [tftp-file]="filename"
)

# How many producers beyond the one the chain needs are drawn for each asset.
# Redundancy is what stops a range being a corridor, and it is a tier dial
# because a learner at easy wants one obvious route and a learner at hard wants
# to find the cheapest of three.
declare -A TIER_REDUNDANCY=( [easy]=0 [normal]=1 [hard]=2 )

# A wrong token costs nothing: the tokens are 8 hex digits behind a fixed prefix
# and nobody arrives at one by guessing. The cap is there so nobody scripts it,
# and it is generous enough that a learner who pastes the same token twice while
# working out the syntax is not near it.
MAX_FLAG_SUBMISSIONS=20

# The vault. One container, on a bridge of its own behind the deepest router,
# with a filter on that router that forwards to it from one address only.
#
# It is deliberately NOT one of the drawn hosts, and that keeps the two halves of
# the range independent: the survey scores exactly what it scored before, and the
# vault is territory the chain opens rather than something a sweep can stumble
# into. Its subnet is excluded from the scoring the same way the attacker's own
# segment is, so the ICMP administratively-prohibited a probe into it comes back
# with is a breadcrumb and never a trap.
VAULT="vault"
VAULT_CTN="${AS}_${LAYER}_${DC}_${VAULT}"

# Where a machine on the chain keeps the token the scorer reads back, and where
# it keeps the copy the learner is meant to find. The scorer's copy is root-owned
# and unreadable by the account the chain logs in as, so it is ground truth
# rather than a second way to get the answer.
FLAG_TRUTH_PATH="/etc/minilabs/flagtoken"
FLAG_PREFIX="MINILABS"

# The account the chain uses on the vault and on an SSH pivot, and the file the
# final flag is read out of. `sudo -l` on the last machine names the one command
# that reads it, which is a misconfiguration a defender fixes with a config
# change rather than anything resembling an exploit.
CHAIN_ACCOUNT="svc-backup"
VAULT_FLAG_FILE="/root/flag.txt"

# ---------------------------------------------------------------------------
# Service profiles.
#
# One script per profile under image/profiles/, named after the token that goes
# into TARGET_PROFILE. spawn.sh copies the drawn profile's script into its
# container and runs it, the same way default_config/<device>.sh works in a
# catalogue lab.
#
# A profile script starts its service, confirms it is listening, and only then
# writes the descriptor score.sh reads back. That order is what makes a profile
# that failed to start score as a port that is not open rather than as a finding
# the learner missed.
PROFILES=(http ftp telnet ssh dns snmp tftp smtp redis rsync proxy mqtt ntp
          syslog jetdirect monitor iperf junk none)

# The transport each service speaks. Six of them are UDP, which is the half of a
# survey a TCP-only range never teaches: a UDP probe that gets no answer is
# `open|filtered` and not `closed`, and telling those apart needs the ICMP port
# unreachable a shut port sends and a filtered one does not.
declare -A PROFILE_PROTO=(
    [http]=tcp   [ftp]=tcp    [telnet]=tcp [ssh]=tcp  [dns]="udp tcp"
    [snmp]=udp   [tftp]=udp   [smtp]=tcp   [redis]=tcp [rsync]=tcp
    [proxy]=tcp  [mqtt]=tcp   [ntp]=udp    [syslog]=udp
    [jetdirect]=tcp [monitor]=tcp [iperf]=tcp [junk]=tcp
)

# The port each service is found on when it is where the registry says it should
# be, and the alternates it is moved to when the seed says otherwise. Telling a
# service by its reply rather than by its port number is the reason the alternates
# exist, so nmap's -sV has something to be right about.
declare -A PROFILE_PORT=(
    [http]=80    [ftp]=21     [telnet]=23  [ssh]=22   [dns]=53
    [snmp]=161   [tftp]=69    [smtp]=25    [redis]=6379 [rsync]=873
    [proxy]=3128 [mqtt]=1883  [ntp]=123    [syslog]=514
    [jetdirect]=9100 [monitor]=9600 [iperf]=5201
)

# A profile with no entry here is never moved off its registered port. DNS, SNMP,
# TFTP, NTP and syslog are all in that class, and for DNS the reason is the one
# that mattered first: the zone transfer at normal and above is the range's one
# shortcut to the whole map, and hiding the port it lives on turns a deliberate
# reward into a coin flip. The other four are infrastructure a scanner reaches by
# name, and moving them would teach that a UDP survey is a port sweep.
declare -A PROFILE_ALT_PORTS=(
    [http]="8080 8000 8081 8888"
    [ftp]="2121 2100"
    [telnet]="2323 2300"
    [ssh]="2222 2022"
    [smtp]="2525 5870"
    [redis]="6380 16379"
    [rsync]="8730 10873"
    [proxy]="8118 3129"
    [mqtt]="1884 8083"
    [jetdirect]="9101 9102"
    [monitor]="9601 9700 9750"
    [iperf]="5202 5301"
)

# Two implementations behind one service class, drawn per host. It costs nothing
# and it means the version half of the scoring is an identification task rather
# than a lookup a learner memorises after two spawns: `http` is lighttpd on one
# range and darkhttpd on the next, and the two announce different names as well
# as different numbers. The profile script reads the version back off its own
# service either way, so the scorer needs to know nothing about which was drawn.
declare -A PROFILE_IMPLS=(
    [http]="lighttpd darkhttpd"
    [ssh]="openssh dropbear"
    [ntp]="chrony openntpd"
)

# The draw pool for a host with no other constraint on it. A profile appears more
# than once to make it commoner: a range where every host runs something exotic
# reads as a puzzle rather than as a network.
PROFILE_POOL=(
    http http http ftp ftp telnet telnet ssh ssh smtp smtp
    snmp snmp redis rsync proxy mqtt ntp tftp syslog jetdirect monitor iperf
)

# Services that never send a byte back. A UDP listener that answers nothing is
# indistinguishable from a filtered port, which is the lesson, but only when the
# ports around it are honest: on a host that drops its shut ports every port
# reads `open|filtered` and the comparison the lesson turns on is gone. So a
# silent service is only ever placed on a host that answers a shut port.
PROFILE_SILENT="syslog"

# How many junk listeners the `noisy` mutator opens on a host it picks.
JUNK_MIN=6
JUNK_MAX=8
# The ports they are drawn from: high, unregistered, and nothing a learner can
# look up. Judging that an open port is not worth further probing is the skill;
# there is no software behind any of these and their descriptor says so.
JUNK_PORTS=(5001 5601 6001 6800 7002 7100 7402 8181 8300 8402 9001 9111
            9333 9418 9700 10001 10500 11211 12000 13720 14000 15000)

# The port range vsftpd hands out for passive data connections. It lives here
# rather than only inside image/profiles/ftp.sh because spawn.sh has to know it
# too: a host that drops its shut ports would otherwise drop its own data
# connections, so an anonymous share could be logged into and no file could be
# read off it. That is what happened to the leaked-account item, and it failed
# only on the seeds where the FTP host also drew the filtered behaviour, which is
# the kind of intermittent defect a per-seed sweep exists to find. Real firewalls
# in front of an FTP server open exactly this range for exactly this reason.
FTP_PASV_MIN=30000
FTP_PASV_MAX=30100

# ---------------------------------------------------------------------------
# Intel items: the findings that need interaction with a service rather than a
# probe and a reply. Each is a token the learner submits with `report intel`, and
# each one is also an UNLOCK in the sense of the table below: something that
# yields a piece of knowledge the range's chain runs on.
#
# The vocabulary is closed and global rather than per range, because `report`
# validates a token before it is recorded and `report` ships in the image, where
# it cannot know which range is spawned. A token that names something this
# particular range does not carry simply scores as a false positive.
#
#   anon-ftp           the FTP service accepts an anonymous login
#   leaked-account     a file on that share names an account used elsewhere
#   leaked-passphrase  a file names the passphrase on a private key
#   leaked-key         a private key sits in a home directory
#   hidden-path        a path on the web service that is not linked from its index
#   default-cred       the account the device family ships with, still in place
#   weak-telnet-pass   the operations account, whose password is in the wordlist
#   zone-transfer      the DNS service serves a full AXFR of its zone
#   snmp-public        SNMP answers the community string it shipped with
#   snmp-map           its interface table names a subnet
#   smtp-vrfy          the mail service confirms whether an account exists
#   tftp-file          a file is readable over TFTP by a name learned elsewhere
#   redis-open         the key-value store answers with no authentication
#   rsync-module       the file-sync daemon lists a module to an anonymous client
#   mqtt-open          the message broker accepts a subscription with no credential
#   open-proxy         the proxy will connect on behalf of anyone who asks
INTEL_TOKENS=(
    anon-ftp leaked-account leaked-passphrase leaked-key hidden-path
    default-cred weak-telnet-pass zone-transfer
    snmp-public snmp-map smtp-vrfy tftp-file redis-open rsync-module
    mqtt-open open-proxy
)

# The device families a telnet host claims to be, and the credential each one
# ships with. The field manual carries this table, so a learner who reads a
# banner naming one of these families can try its default in a single login. It
# is fixed across seeds on purpose: a default credential is only a default if it
# is written down somewhere public, and the manual is this range's public.
declare -A DEFAULT_CRED=(
    [acc-sw]="admin:admin"
    [tng-rtr]="cisco:cisco"
    [wap-ac]="root:calvin"
    [pdu-e]="apc:apc"
    [ups-net]="upsadm:upsadm"
    [cam-nvr]="admin:9999"
    [bms-ctl]="operator:operator"
    [kvm-ip]="ADMIN:ADMIN"
)
DEVICE_FAMILIES=(acc-sw tng-rtr wap-ac pdu-e ups-net cam-nvr bms-ctl kvm-ip)

# The paths http-enum knows to guess. Drawn from, so a hidden path is found by a
# scanner working through a fingerprint list rather than by reading the index.
HIDDEN_PATHS=("/admin/" "/backup/" "/phpmyadmin/" "/webadmin/" "/manager/")

# ---------------------------------------------------------------------------
# The organisation the range belongs to.
#
# One is drawn per spawn, and everything a learner reads while enumerating comes
# out of it: the zone name, the hostnames, the account names, the device
# families, the web copy and the text of the handover note. It is cosmetic in the
# sense that no address and no port depends on it, and it is the highest ratio of
# felt variety to code in the range, because a learner who has read one handover
# note once recognises it at a glance and stops reading. Skipping the reading is
# skipping the enumeration step the note exists to teach.
ORGS=(freight hospital council isp university)

declare -A ORG_NAME=(
    [freight]="Kiwi Freight Ltd"
    [hospital]="Waitemata Health Trust"
    [council]="Riverton City Council"
    [isp]="Southcape Networks"
    [university]="Tarndale University, Engineering"
)
declare -A ORG_ZONE=(
    [freight]="kiwifreight.lab"
    [hospital]="waitemata-health.lab"
    [council]="riverton.govt.lab"
    [isp]="southcape.lab"
    [university]="eng.tarndale.lab"
)
# The prefix every drawn hostname starts with, so a reverse lookup or a banner
# reads as one estate rather than as nine unrelated machines.
declare -A ORG_PREFIX=(
    [freight]="kfl" [hospital]="wht" [council]="rvc" [isp]="scn" [university]="tue"
)
# The team whose shared account the chain runs through, and the accounts a leaked
# note can name.
declare -A ORG_TEAM=(
    [freight]="network operations"
    [hospital]="clinical systems"
    [council]="ICT services"
    [isp]="the NOC"
    [university]="the department's technicians"
)
declare -A ORG_ACCOUNTS=(
    [freight]="netadmin opsuser fieldsvc dcadmin"
    [hospital]="wardsvc biomed clinops itdesk"
    [council]="rvcadmin siteops permits netsvc"
    [isp]="nocuser peering fieldeng ixadmin"
    [university]="labtech eng-ops research netops"
)
# The sites a schedule or an inventory names. Flavour, and the reason a stale
# record in a zone reads as plausible rather than as an obvious plant.
declare -A ORG_SITES=(
    [freight]="Auckland Tauranga Christchurch"
    [hospital]="North Shore Waitakere Rodney"
    [council]="Civic Riverside Depot"
    [isp]="Core-A Core-B Exchange"
    [university]="Block-C Workshop Annex"
)
# What the document drop holds, and what the organisation does with it.
declare -A ORG_DROP=(
    [freight]="freight manifests"
    [hospital]="equipment service reports"
    [council]="consent scans"
    [isp]="circuit records"
    [university]="lab bookings"
)
# The device families this organisation buys. A range draws its telnet hosts from
# its own organisation's list, so the estate is consistent.
declare -A ORG_FAMILIES=(
    [freight]="acc-sw tng-rtr pdu-e"
    [hospital]="acc-sw ups-net bms-ctl"
    [council]="acc-sw cam-nvr pdu-e"
    [isp]="tng-rtr acc-sw kvm-ip"
    [university]="acc-sw wap-ac kvm-ip"
)

# ---------------------------------------------------------------------------
# Range mutators: one drawn word that changes how the whole spawn feels.
#
# A post-processing pass over the drawn range rather than a separate kind of
# range. It changes the TEXTURE and not the contents, which is why it is the
# cheapest replayability device here: two ranges with the same shape, the same
# host count and the same services are still two different afternoons when one of
# them answers no echo request and the other has every service on the wrong port.
#
#   quiet        most hosts drop echo requests: a ping sweep is not host discovery
#   noisy        three hosts open six to eight listeners with nothing behind them
#   relocated    every service that can be moved is: ports do not name services
#   chatty       SNMP on most hosts: the interface tables are a second map
#   locked-down  shut ports are dropped rather than refused, nearly everywhere
#   legacy       telnet, TFTP and FTP heavy, and no SSH anywhere
#   segmented    an extra dead subnet, and one of them answers admin-prohibited
#   vanilla      no modifier
MUTATORS=(vanilla quiet noisy relocated chatty locked-down legacy segmented)

# `legacy` removes SSH from the draw, and a four-layer chain pivots through an
# SSH host, so the two cannot both hold. The mutator is drawn from the pool minus
# this one on a range that deep.
MUTATOR_NEEDS_SSH="legacy"

# ---------------------------------------------------------------------------
# Host classes.
#
# Server, workstation, network device, embedded appliance. The class constrains
# which profiles a host may draw and is readable from four weak signals rather
# than from `nmap -O`, which reports Linux for all fifteen containers because all
# fifteen are Linux. Inferring a class from several signals that each mean little
# on their own is what fingerprinting actually is, and it is worth teaching that
# way rather than as a flag on a scanner.
#
#   the initial TTL          set per container, so an observed TTL says which
#   the vendor OUI           the first three octets of the MAC, on the local segment
#   the hostname and banner  what the machine calls itself
#   the service mix          a PDU does not run a file-sync daemon
CLASSES=(server workstation netdev appliance)

# net.ipv4.ip_default_ttl, one of the sysctls that only takes at `docker run`.
# Written over `docker exec` it silently does nothing, because Docker mounts
# /proc/sys read-only in an unprivileged container, which is the same trap the
# mac-flooding lab's sysctls fell into.
declare -A CLASS_TTL=( [server]=64 [workstation]=128 [netdev]=255 [appliance]=64 )

# Real vendor OUIs, so a lookup against a public OUI list gives the answer the
# range intends. Dell, Intel, Cisco and APC in that order.
declare -A CLASS_OUI=(
    [server]="00:14:22" [workstation]="3c:97:0e"
    [netdev]="00:1b:0d"  [appliance]="00:c0:b7"
)

# The profiles each class may run. A class is evidence precisely because the
# service mix is not uniform across the four.
declare -A CLASS_PROFILES=(
    [server]="http ftp ssh dns smtp redis rsync mqtt proxy iperf snmp"
    [workstation]="http ssh iperf none"
    [netdev]="telnet snmp tftp syslog ssh"
    [appliance]="telnet http snmp jetdirect monitor ntp"
)

# The hostname a class's machine is given, after the organisation's prefix.
declare -A CLASS_HOSTPART=(
    [server]="app db file mail web core"
    [workstation]="ws desk pc term"
    [netdev]="sw rtr acc dist"
    [appliance]="prn sens ctl cam gate"
)

# What the SNMP profile reports as sysDescr, which is the one place a machine
# says its class out loud. Templated with the organisation's name.
declare -A CLASS_SYSDESCR=(
    [server]="Linux server, general purpose"
    [workstation]="Desktop workstation"
    [netdev]="Managed access switch, 24-port"
    [appliance]="Embedded appliance controller"
)

# ---------------------------------------------------------------------------
# Decoys: claims that look like findings and score as false positives.
#
# The penalty structure exists and was barely used, so every one of these is a
# thing a learner who reports what they READ rather than what they PROBED pays
# for. None of them is a trick: each is a real artefact of a real network that
# has drifted, and each is checkable in one command.
#
#   stale-dns        two A records for addresses that hold nothing: -2 each
#   snmp-ghost       an administratively-down interface naming a subnet that is
#                    not routed anywhere: -3 as a subnet claim
#   robots-404       a robots.txt naming a path the server answers 404 for
#   decoy-flag       a correctly shaped token on the anonymous share, from a
#                    rebuild that never finished: scores zero, rewards reading
#   masked-banner    one web host that announces no version, so the version has
#                    to come from behaviour or not at all
#   no-time-exceeded one router that does not send ICMP time-exceeded, so a
#                    traceroute through it shows a gap where a hop should be
DECOYS=(stale-dns snmp-ghost robots-404 decoy-flag masked-banner no-time-exceeded)

# The account names a handover note leaks come from the organisation now; this is
# the fallback for a range drawn before one was chosen.
LEAK_ACCOUNTS=(netadmin opsuser fieldsvc dcadmin)

# Ports the per-port state draw picks from when it makes a shut port filtered
# rather than refused. All of them are ports a scanner's default list probes, so
# the difference between `closed` and `filtered` shows up in a scan a learner was
# going to run anyway.
FILTER_CANDIDATES=(135 139 445 1433 3306 3389 5432 5900 8443 11211)

# The words a vault key's passphrase is built from. Deliberately NOT the range's
# password list: this passphrase is found in a file, not guessed, and putting it
# on a wordlist would turn hydra into a shortcut past the second branch of the
# chain that it exists to force. Three words and two digits is long enough that
# nothing in this range's tooling would arrive at it by trying.
PASSPHRASE_WORDS=(
    harbour tundra basalt lantern quarry meridian thistle cobalt
    saltmarsh gantry kestrel plinth harrow verdigris cinder tessera
)

# Fifty common passwords, baked into the image. The operations account's password
# is one of them, deliberately not at the top, so a learner watches hydra work.
PASS_LIST="/usr/share/minilabs/passwords.txt"

# ---------------------------------------------------------------------------
# Scoring weights. One place, because the handout prints them and selftest.sh
# checks them.
#
# The map categories are what make a randomised topology worth the build: at easy
# the learner is handed the one subnet and scores nothing for it, and at hard the
# map is around a quarter of the range.
W_SUBNET=4      ; P_SUBNET=3     # per live segment found / per subnet that does not exist
W_HOPS=2        ;                # per segment at the right distance; only on a segment found
W_ROUTER=3      ; P_ROUTER=3      # per router interface / per address wrongly called one
W_HOST=2        ; P_HOST=2       # per live host / per address claimed that is not live
W_PORT=3        ; P_PORT=1       # per open port / per port claimed open that is not
W_SERVICE=2     ;                # per correct service name, on a port genuinely open
W_VERSION=3     ;                # per correct version, on a port genuinely open
W_INTEL=5       ; P_INTEL=3      # per item / per item claimed on a host that does not carry it
W_CLASS=2       ; P_CLASS=2      # per host classified correctly / per one classified wrongly

# P_ROUTER and P_INTEL are this range's two additions to the weights the lesson
# plan sets out, and both are there to keep the plan's own invariant true: a
# submission of everything must score below an empty one. Every category the plan
# names already penalises a claim that is not so; these two did not, and an
# unpenalised category is one a learner can spray.
#
# Intel is six tokens over at most nine hosts, so without P_INTEL there are
# fifty-four lines worth up to +5 each and no risk in writing all of them. Router
# interfaces are worse, because every segment gateway is the .1 of its subnet by
# design, so `report router <x>.1` for every third octet in the /16 would harvest
# the whole category without a single probe. With both penalties the scripted
# false-positive player finishes on the floor, which is where it belongs.

# The floor. A submission of every address in a segment plus a spray of ports
# cannot score below an empty one; the penalties are what make it score worse.
SCORE_FLOOR=0

# ---------------------------------------------------------------------------
# Container naming. The platform convention, with L4 marking the layer:
# <AS>_L4_<DC>_<token>. One prefix covers every container including the switch,
# so status and teardown select the range with a single filter.
#
# Host tokens are host1..host9 and carry no service name, for the same reason
# they do in the fixed scanning lab: `docker ps` and spawn.sh's log lines are
# both things a learner sees before they have scanned anything, and what runs
# where is the exercise. shell.sh holds its node list back until Score has run
# for the same reason.
SW="S1"
SW_CTN="${AS}_${LAYER}_${DC}_${SW}"
ATTACKER_CTN="${AS}_${LAYER}_${DC}_attacker"
CTN_PREFIX="${AS}_${LAYER}_${DC}_"

ctn_of()     { echo "${CTN_PREFIX}$1"; }
sw_port_of() { echo "${AS}-$1"; }

# Interface names. The attacker's single NIC and each router's links are named
# after what sits at the far end, so `ip -brief addr` on a router reads as a map.
ATT_IF="${AS}-ext"
HOST_IF="${AS}-${SW}"          # every target host's only NIC

# ---------------------------------------------------------------------------
SWITCH_IMAGE="miniinterneteth/d_switch"
HOST_IMAGE="d_host_range"

# Open vSwitch is started explicitly instead of through the image's supervisord
# entrypoint, so --no-mlockall can be passed. Under a rootless daemon
# CAP_IPC_LOCK is confined to the user namespace and cannot exceed
# RLIMIT_MEMLOCK, so the first thread stack past that limit fails to lock and
# ovs-vswitchd dies with "pthread_create failed". Locking buys a lab switch
# nothing, and the resulting datapath under a rootful daemon is identical.
SWITCH_CMD='/usr/share/openvswitch/scripts/ovs-ctl start --no-mlockall --system-id=random && exec sleep infinity'

# ---------------------------------------------------------------------------
# The seeded PRNG.
#
# Reproducibility is the range's other central invariant: a (tier, seed) pair
# must produce the same shape, the same segment count and depth, the same
# addresses, the same services, the same versions and the same behaviour flags,
# so that a tutor can set one seed for a class and a badly generated range can be
# pinned in a bug report rather than described.
#
# That means the generator reads nothing that varies outside the seed. Seed this
# once and take every draw from it in a fixed order: no $RANDOM, no `shuf`
# without --random-source, no clock, no hostname, and nothing that depends on the
# order `docker ps` happens to return.
#
# Appending a new drawn attribute at the END of the sequence keeps existing seeds
# stable. Inserting one in the middle changes every range, so once seeds are
# being shared, append rather than insert.
#
# The generator is a 64-bit linear congruential sequence (Knuth's MMIX constants)
# masked to 63 bits, with the output taken from the high half. The low bits of an
# LCG are famously short-period; drawing from bit 17 upwards keeps them out of
# every value this range uses.
_RNG_STATE=0

# Every draw returns through $RAND rather than through stdout, and that is not a
# style choice. A command substitution runs its body in a subshell, so `v=$(rand
# 10)` would advance the generator's state inside a child process and throw the
# advance away when it exited: every call would return the same number and any
# rejection loop built on it would never terminate. Assigning to a global keeps
# the state in the caller's own shell.
RAND=0

rng_seed() {   # <integer seed> [salt string]
    # The salt is folded in so that the same seed at two tiers is two different
    # ranges rather than the same addresses behind a different shape. Without it
    # the tier only changes how many draws the shape consumes, and a tutor
    # comparing easy 4711 against hard 4711 would be handing out the same /16 and
    # frequently the same subnets twice.
    local _salt=0 _i _c
    if [ -n "${2:-}" ]; then
        for (( _i = 0; _i < ${#2}; _i++ )); do
            printf -v _c '%d' "'${2:_i:1}"
            _salt=$(( ( _salt * 131 + _c ) & 0xFFFFFFFF ))
        done
    fi
    _RNG_STATE=$(( ( ( $1 ^ ( _salt * 2654435761 ) ) * 6364136223846793005 \
                     + 1442695040888963407 ) & 0x7FFFFFFFFFFFFFFF ))
    rng_next; rng_next    # discard two, so adjacent seeds do not start alike
}

rng_next() {
    _RNG_STATE=$(( ( _RNG_STATE * 6364136223846793005 + 1442695040888963407 ) & 0x7FFFFFFFFFFFFFFF ))
}

rand() {   # rand <n> -> $RAND in 0 .. n-1
    rng_next
    RAND=$(( ( _RNG_STATE >> 17 ) % $1 ))
}

rand_range() {   # rand_range <lo> <hi> -> $RAND in lo .. hi inclusive
    rand $(( $2 - $1 + 1 ))
    RAND=$(( $1 + RAND ))
}

rand_pick() {   # rand_pick <item...> -> $RAND is one item
    rand $#
    local _i=$(( RAND + 1 ))
    RAND="${!_i}"
}

# Fisher-Yates over the named array, in place. Deterministic given the state.
rand_shuffle() {   # rand_shuffle <array-name>
    local -n _arr="$1"
    local i j tmp
    for (( i = ${#_arr[@]} - 1; i > 0; i-- )); do
        rand $(( i + 1 )); j="$RAND"
        tmp="${_arr[$i]}"; _arr[$i]="${_arr[$j]}"; _arr[$j]="$tmp"
    done
}

# A coin that comes up heads <num> times in <den>.
rand_chance() {   # rand_chance <num> <den>
    rand "$2"
    [ "$RAND" -lt "$1" ]
}

# ---------------------------------------------------------------------------
# Addressing helpers. These are pure arithmetic on strings and hold no addresses
# of their own, so they are shared rather than confined to generate.sh.

# The /24 an address sits in, as a CIDR string.
net24_of() {   # <a.b.c.d> -> a.b.c.0/24
    local ip="$1"
    echo "${ip%.*}.0/24"
}

# The network address of <ip>/<len>, for the two prefix lengths this range uses.
net_of() {   # <a.b.c.d> <prefixlen>
    local ip="$1" len="$2"
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    case "$len" in
        24) echo "$a.$b.$c.0/24" ;;
        30) echo "$a.$b.$c.$(( d - d % 4 ))/30" ;;
        *)  echo "$ip/$len" ;;
    esac
}

# ---------------------------------------------------------------------------
# Load the drawn range. Every script except generate.sh calls this after sourcing
# lib.sh, so that nothing outside generate.sh has to know how a range is written
# down. Fails loudly when no range has been generated, because every caller's
# next line would otherwise read an unset address.
load_topology() {
    if [ ! -f "$TOPO_ENV" ]; then
        echo "no range has been generated: $TOPO_ENV is missing" >&2
        echo "run Spawn (or scripts/spawn.sh <tier> [seed]) first" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    source "$TOPO_ENV"
}

# True when the range's containers are up. Cheap, and used by score, reveal and
# status to tell "not spawned" from "spawned and empty".
# The listing is captured and then matched, rather than piped into `grep -q`.
# Under `set -o pipefail` a `grep -q` that matches early closes the pipe, the
# producer dies on SIGPIPE, and the pipeline reports failure even though the
# match was found. Every caller here runs with pipefail set.
range_is_up() {
    local names
    names="$( docker ps --format '{{.Names}}' 2>/dev/null )"
    case $'\n'"$names"$'\n' in *$'\n'"$ATTACKER_CTN"$'\n'*) return 0 ;; esac
    return 1
}

# ---------------------------------------------------------------------------
# True when anything in <dir> is newer than the image built from it. Without it
# an image is only rebuilt when it is MISSING, so an edit under image/ never
# reaches a machine that built the image once.
image_older_than_source() {   # <image> <dir>
    local img="$1" dir="$2" built newest
    built="$( docker image inspect -f '{{.Created}}' "$img" 2>/dev/null )" || return 1
    built="$( date -d "$built" +%s 2>/dev/null )" || return 1   # non-GNU date: skip the check
    newest="$( find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 )"
    [ -n "$newest" ] || return 1
    [ "${newest%.*}" -gt "$built" ]
}

ensure_images() {
    if ! docker image inspect "$SWITCH_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] pulling $SWITCH_IMAGE (first run only)"
        docker pull "$SWITCH_IMAGE" >/dev/null \
            || { echo "failed to pull $SWITCH_IMAGE" >&2; return 1; }
    fi
    if ! docker image inspect "$HOST_IMAGE" >/dev/null 2>&1; then
        echo "[spawn] building $HOST_IMAGE from $LAB_DIR/image (first run only)"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to build $HOST_IMAGE" >&2; return 1; }
    elif image_older_than_source "$HOST_IMAGE" "$LAB_DIR/image"; then
        echo "[spawn] rebuilding $HOST_IMAGE: $LAB_DIR/image changed since it was built"
        docker build -t "$HOST_IMAGE" "$LAB_DIR/image" \
            || { echo "failed to rebuild $HOST_IMAGE" >&2; return 1; }
    fi
}

# ---------------------------------------------------------------------------
# Privileged host networking, performed from a helper container.
#
# Wiring needs CAP_NET_ADMIN to create a veth pair and CAP_SYS_ADMIN to enter a
# container's network namespace and rename the interface inside it. Rather than
# require root on the host, a throwaway --privileged container holds them.
#
# The helper keeps a network namespace of its own (--network=none). Both ends of
# every veth pair are moved out into range containers, so the namespace the pair
# is created in never matters, and asking for the host's namespace only breaks
# the helper under a rootless daemon. --pid=host stays: it is what makes each
# container's /proc/<pid>/ns/net reachable for the moves.
#
# Renames run through `nsenter --net`, never `ip netns exec`: iproute2 remounts
# /sys on every namespace switch and a user namespace forbids that, while the
# rename itself is pure netlink and needs no sysfs.
HELPER_CTN="$( ctn_of netadmin_helper )"

helper_start() {
    docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true
    docker run -d --rm --name "$HELPER_CTN" \
        --privileged --network=none --pid=host \
        "$HOST_IMAGE" sleep 600 >/dev/null
    for _ in $(seq 1 40); do
        if docker exec "$HELPER_CTN" true >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    echo "helper container $HELPER_CTN did not become ready" >&2
    return 1
}

helper() { docker exec "$HELPER_CTN" "$@"; }

helper_stop() { docker rm -f "$HELPER_CTN" >/dev/null 2>&1 || true; }
