require 'tempfile'

def run_suricata(pcap, rules, suricata:, **_kwargs)
  Tempfile.create('suricata.rules') do |suricata_rules|
    suricata_rules.puts(rules.join("\n"))
    suricata_rules.close

    ::Dir.mktmpdir do |outdir|
      system("#{ suricata } -c \"#{ ::File.join(__dir__, 'suricata.conf') }\" -s \"#{ suricata_rules.to_path }\" -k none -r \"#{ pcap }\" -l \"#{ outdir }\"")

      return {
        errors: ::File.readlines(::File.join(outdir, 'suricata.log')),
        results: ::File.readlines(::File.join(outdir, 'eve.json'))
                       .map { |l| ::JSON.parse(l) }
                       .select { |e| e['event_type'] == 'alert' },
      }.compact
    end
  end
end
