#!/usr/bin/awk -f
#
# Annotates the SCID / UTC / SSP lines emitted by `make defect`.
#
# For every sub-satellite-point line it compares latitude and longitude against
# the previous one and appends either "did not move" or the great-circle
# distance travelled since the previous frame.
#
# Everything printed here is derived from the values in the stream. Nothing is
# hardcoded, so this cannot assert motion the run did not actually produce.

function rad(d) { return d * 3.141592653589793 / 180.0 }

function gcmiles(a1, o1, a2, o2,   p1, p2, dp, dl, h) {
    p1 = rad(a1); p2 = rad(a2)
    dp = p2 - p1; dl = rad(o2 - o1)
    h = sin(dp / 2) ^ 2 + cos(p1) * cos(p2) * sin(dl / 2) ^ 2
    if (h > 1) h = 1
    # 6371 km mean Earth radius, expressed in statute miles
    return 2 * 3958.8 * atan2(sqrt(h), sqrt(1 - h))
}

/SSP LAT/ {
    lat = ""; lon = ""
    for (i = 1; i <= NF; i++) {
        if ($i == "LAT=") lat = $(i + 1)
        if ($i == "LON=") lon = $(i + 1)
    }
    if (!seen) {
        seen = 1
        plat = lat; plon = lon
        print
        next
    }
    if (lat == plat && lon == plon) {
        print $0 "   <-- did not move"
    } else {
        printf "%s   <== JUMPED %d miles in one frame\n", $0, gcmiles(plat, plon, lat, lon)
    }
    plat = lat; plon = lon
    next
}

{ print }
