param ($networkPrefix, $dnsServer)

$start = 1
$end = 254

for ($i = $start; $i -le $end; $i++) {
    $ip = "$networkPrefix.$i"

    try {
        $result = Resolve-DnsName -Name $ip -Server $dnsServer -ErrorAction stop
        if ($result) {
            "$ip - " + $result.NameHost
        } 

    } catch {
            # Do nothing.
        }
}
