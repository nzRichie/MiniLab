#!/bin/bash
# Victim starter config — a plain host with no defences (the defender side arrives
# with the gap to close; see solution/ for the reference mitigations).
ip address add 100.0.0.20/24 dev 100-S1
ip route add default via 100.0.0.1 2>/dev/null || true
