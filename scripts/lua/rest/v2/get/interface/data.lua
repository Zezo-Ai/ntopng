--
-- (C) 2013-24 - ntop.org
--
local dirs = ntop.getDirs()

package.path = dirs.installdir .. "/scripts/lua/modules/?.lua;" .. package.path
package.path = dirs.installdir .. "/scripts/lua/modules/vulnerability_scan/?.lua;" .. package.path

-- trace_script_duration = true

require "lua_utils"
local periodic_activities_utils = require "periodic_activities_utils"
local cpu_utils = require("cpu_utils")
local callback_utils = require("callback_utils")
local recording_utils = require("recording_utils")
local rest_utils = require("rest_utils")
local auth = require "auth"
local vs_utils = require "vs_utils"

--
-- Read information about an interface
-- Example: curl -u admin:admin -H "Content-Type: application/json" -d '{"ifid": "1"}' http://localhost:3000/lua/rest/v2/get/interface/data.lua
--
-- NOTE: in case of invalid login, no error is returned but redirected to login
--

local rc = rest_utils.consts.success.ok
local res = {}

local ifid = _GET["ifid"]
local iffilter = _GET["iffilter"]

if isEmptyString(ifid) and isEmptyString(iffilter) then
    rc = rest_utils.consts.err.invalid_interface
    rest_utils.answer(rc)
    return
end

local function userHasRestrictions()
    local allowed_nets = ntop.getPref("ntopng.user." .. (_SESSION["user"] or "") .. ".allowed_nets")

    for _, net in pairs(split(allowed_nets, ",")) do
        if not isEmptyString(net) and net ~= "0.0.0.0/0" and net ~= "::/0" then
            return true
        end
    end

    return false
end

local function countHosts()
    local res = {
        local_hosts = 0,
        hosts = 0
    }

    for host, info in callback_utils.getHostsIterator(false --[[no details]]) do
        if info.localhost then
            res.local_hosts = res.local_hosts + 1
        end

        res.hosts = res.hosts + 1
    end

    return res
end

function dumpInterfaceStats(ifid)
    -- main interface stats used by periodic data.lua call
    if (_GET["type"] == "summary") then
        return dumpBriefInterfaceStats(ifid)
    end

    local interface_name = getInterfaceName(ifid)
    interface.select(ifid .. '')

    local ifstats = interface.getStats()
    local drops = 0

    if interface.isView() then
        local zmq_stats = {}
        for interface_name, _ in pairsByKeys(interface.getIfNames() or {}) do
            interface.select(interface_name)
            local tmp = interface.getStats()
            for k, v in pairs(tmp.zmqRecvStats or {}) do
                zmq_stats[k] = (zmq_stats[k] or 0) + v
            end
            for k, v in pairs(tmp.exporters or {}) do
                drops = v["num_drops"] + drops
            end
        end
        ifstats.zmqRecvStats = zmq_stats
        interface.select(ifstats.id)
    elseif (ifstats) then
        drops = ifstats.stats_since_reset.drops
    end

    local res = {}
    if (ifstats ~= nil) then
        local uptime = ntop.getUptime()
        local prefs = ntop.getPrefs()

        -- Round up
        local hosts_pctg = math.floor(1 + ((ifstats.stats.hosts * 100) / prefs.max_num_hosts))
        local flows_pctg = math.floor(1 + ((ifstats.stats.flows * 100) / prefs.max_num_flows))
        local macs_pctg = math.floor(1 + ((ifstats.stats.current_macs * 100) / prefs.max_num_hosts))

        res["ifid"] = ifid
        res["ifname"] = interface_name
        res["speed"] = getInterfaceSpeed(ifstats.id)
        res["periodic_stats_update_frequency_secs"] = ifstats.periodic_stats_update_frequency_secs
        -- network load is used by web pages that are shown to the user
        -- so we must return statistics since the latest (possible) reset
        res["packets"] = ifstats.stats_since_reset.packets
        res["bytes"] = ifstats.stats_since_reset.bytes
        res["drops"] = drops

        local tot_pkt = 0
        local tot_pkt_drops = 0

        for interface_id, probes_list in pairs(ifstats.probes or {}) do
            for source_id, probe_info in pairs(probes_list or {}) do
                tot_pkt = tot_pkt + probe_info["packets.total"]
                tot_pkt_drops = tot_pkt_drops + probe_info["packets.drops"]
            end
        end

        res["tot_nprobe_pkts"] = tot_pkt
        res["tot_pkt_drops"]   = tot_pkt_drops

        if ifstats.stats_since_reset.discarded_probing_packets then
            res["discarded_probing_packets"] = ifstats.stats_since_reset.discarded_probing_packets
            res["discarded_probing_bytes"] = ifstats.stats_since_reset.discarded_probing_bytes
        end

        res["throughput_bps"] = ifstats.stats.throughput_bps;
        res["throughput_pps"] = ifstats.stats.throughput_pps;

        if prefs.is_dump_flows_enabled == true then
            res["flow_export_drops"] = ifstats.stats_since_reset.flow_export_drops
            res["flow_export_rate"] = ifstats.stats_since_reset.flow_export_rate
            res["flow_export_count"] = ifstats.stats_since_reset.flow_export_count
        end

        if auth.has_capability(auth.capabilities.alerts) then
            res["engaged_alerts"] = ifstats["num_alerts_engaged"] or 0
            res["dropped_alerts"] = ifstats["num_dropped_alerts"] or 0
            res["host_dropped_alerts"] = ifstats["num_host_dropped_alerts"] or 0
            res["flow_dropped_alerts"] = ifstats["num_flow_dropped_alerts"] or 0
            res["other_dropped_alerts"] = ifstats["num_other_dropped_alerts"] or 0

            -- Active flow alerts: total
            res["alerted_flows"] = ifstats["num_alerted_flows"] or 0

            -- Active flow alerts: breakdown
            res["alerted_flows_notice"] = ifstats["num_alerted_flows_notice"] or 0
            res["alerted_flows_warning"] = ifstats["num_alerted_flows_warning"] or 0
            res["alerted_flows_error"] = ifstats["num_alerted_flows_error"] or 0

            -- Engaged alerts: breakdown
            res["engaged_alerts_notice"] = ifstats["num_alerts_engaged_by_severity"]["notice"]
            res["engaged_alerts_warning"] = ifstats["num_alerts_engaged_by_severity"]["warning"]
            res["engaged_alerts_error"] = ifstats["num_alerts_engaged_by_severity"]["error"]
        end

        if periodic_activities_utils.have_degraded_performance() then
            res["degraded_performance"] = true
        end

        if not userHasRestrictions() then
            res["num_flows"] = ifstats.stats.flows
            res["num_hosts"] = ifstats.stats.hosts
            res["num_local_hosts"] = ifstats.stats.local_hosts
            res["num_devices"] = ifstats.stats.devices
            res["num_rcvd_only_hosts"] = ifstats.stats.hosts_rcvd_only
            res["num_local_rcvd_only_hosts"] = ifstats.stats.local_rcvd_only_hosts
        else
            local num_hosts = countHosts()
            res["num_hosts"] = num_hosts.hosts
            res["num_local_hosts"] = num_hosts.local_hosts
        end

        res["epoch"] = os.time()
        res["localtime"] = os.date("%H:%M:%S %z", res["epoch"])
        res["uptime_sec"] = uptime
        res["uptime"] = secondsToTime(uptime)
        if ntop.isPro() then
            local product_info = ntop.getInfo(true)

            if product_info["pro.out_of_maintenance"] then
                res["out_of_maintenance"] = true
            end
        end
        res["system_host_stats"] = cpu_utils.systemHostStats()
        res["hosts_pctg"] = hosts_pctg
        res["flows_pctg"] = flows_pctg
        res["macs_pctg"] = macs_pctg
        res["remote_pps"] = ifstats.remote_pps
        res["remote_bps"] = ifstats.remote_bps
        res["is_view"] = ifstats.isView

        if isAdministrator() then
            res["num_live_captures"] = ifstats.stats.num_live_captures
        end

        res["local2remote"] = ifstats["localstats"]["bytes"]["local2remote"]
        res["remote2local"] = ifstats["localstats"]["bytes"]["remote2local"]
        res["bytes_upload"] = ifstats["eth"]["egress"]["bytes"]
        res["bytes_download"] = ifstats["eth"]["ingress"]["bytes"]
        res["packets_upload"] = ifstats["eth"]["egress"]["packets"]
        res["packets_download"] = ifstats["eth"]["ingress"]["packets"]
        res["bytes_upload_since_reset"] = ifstats.traffic_sent_since_reset
        res["bytes_download_since_reset"] = ifstats.traffic_rcvd_since_reset
        res["packets_upload_since_reset"] = ifstats.packets_sent_since_reset
        res["packets_download_since_reset"] = ifstats.packets_rcvd_since_reset

        res["num_local_hosts_anomalies"] = ifstats.anomalies.num_local_hosts_anomalies
        res["num_remote_hosts_anomalies"] = ifstats.anomalies.num_remote_hosts_anomalies

        local ingress_thpt = ifstats["eth"]["ingress"]["throughput"]
        local egress_thpt = ifstats["eth"]["egress"]["throughput"]
        res["throughput"] = {
            download = {
                bps = ingress_thpt["bps"],
                bps_trend = ingress_thpt["bps_trend"],
                pps = ingress_thpt["pps"],
                pps_trend = ingress_thpt["pps_trend"]
            },
            upload = {
                bps = egress_thpt["bps"],
                bps_trend = egress_thpt["bps_trend"],
                pps = egress_thpt["pps"],
                pps_trend = egress_thpt["pps_trend"]
            }
        }

        local download_stats = ifstats["download_stats"]
        local upload_stats = ifstats["upload_stats"]

        res["download_upload_chart"] = {
            download = download_stats,
            upload = upload_stats
        }

        if ntop.isnEdge() and ifstats.type == "netfilter" and ifstats.netfilter then
            res["netfilter"] = ifstats.netfilter
        end

        if (ifstats.zmqRecvStats ~= nil) then
            if ifstats.zmqRecvStats_since_reset then
                -- override stats with the values calculated from the latest user reset
                -- for consistency with if_stats.lua
                for k, v in pairs(ifstats.zmqRecvStats_since_reset) do
                    ifstats.zmqRecvStats[k] = v
                end
            end

            res["zmqRecvStats"] = {}
            res["zmqRecvStats"]["flows"] = ifstats.zmqRecvStats.flows
            res["zmqRecvStats"]["dropped_flows"] = ifstats.zmqRecvStats.dropped_flows
            res["zmqRecvStats"]["events"] = ifstats.zmqRecvStats.events
            res["zmqRecvStats"]["counters"] = ifstats.zmqRecvStats.counters
            res["zmqRecvStats"]["zmq_msg_rcvd"] = ifstats.zmqRecvStats.zmq_msg_rcvd
            res["zmqRecvStats"]["zmq_msg_drops"] = ifstats.zmqRecvStats.zmq_msg_drops
            res["zmqRecvStats"]["zmq_avg_msg_flows"] = math.max(1, (ifstats.zmqRecvStats.flows or 0) /
                ((ifstats.zmqRecvStats.zmq_msg_rcvd or 0) + 1))

            res["zmq.num_flow_exports"] = ifstats["zmq.num_flow_exports"] or 0
            res["zmq.num_exporters"] = ifstats["zmq.num_exporters"] or 0

            res["zmq.drops.export_queue_full"] = ifstats["zmq.drops.export_queue_full"] or 0
            res["zmq.drops.flow_collection_drops"] = ifstats["zmq.drops.flow_collection_drops"] or 0
            res["zmq.drops.flow_collection_udp_socket_drops"] =
                ifstats["zmq.drops.flow_collection_udp_socket_drops"] or 0
        end

        res["tcpPacketStats"] = {}
        res["tcpPacketStats"]["retransmissions"] = ifstats.tcpPacketStats.retransmissions
        res["tcpPacketStats"]["out_of_order"] = ifstats.tcpPacketStats.out_of_order
        res["tcpPacketStats"]["lost"] = ifstats.tcpPacketStats.lost

        if interface.isSyslogInterface() then
            res["syslog"] = {}
            res["syslog"]["tot_events"] = ifstats.syslog.tot_events
            res["syslog"]["malformed"] = ifstats.syslog.malformed
            res["syslog"]["dispatched"] = ifstats.syslog.dispatched
            res["syslog"]["unhandled"] = ifstats.syslog.unhandled
            res["syslog"]["alerts"] = ifstats.syslog.alerts
            res["syslog"]["host_correlations"] = ifstats.syslog.host_correlations
            res["syslog"]["flows"] = ifstats.syslog.flows
        end

        if (ifstats["profiles"] ~= nil) then
            res["profiles"] = ifstats["profiles"]
        end

        if recording_utils.isAvailable() then
            if recording_utils.isEnabled(ifstats.id) then
                if recording_utils.isActive(ifstats.id) then
                    res["traffic_recording"] = "recording"
                else
                    res["traffic_recording"] = "failed"
                end
            end

            if recording_utils.isEnabled(ifstats.id) then
                local jobs_info = recording_utils.extractionJobsInfo(ifstats.id)
                if jobs_info.ready > 0 then
                    res["traffic_extraction"] = "ready"
                elseif jobs_info.total > 0 then
                    res["traffic_extraction"] = jobs_info.total
                end
                res["traffic_extraction_num_tasks"] = jobs_info.total
            end
        end

        -- Adding a preference if active discovery is enabled
        res["active_discovery_active"] = ntop.getPref("ntopng.prefs.is_periodic_network_discovery_running.ifid_" ..
            interface.getId()) == "1"
    end

    return res
end

function dumpBriefInterfaceStats(ifid)
    local interface_name = getInterfaceName(ifid)
    interface.select(ifid .. '')

    local ifstats = interface.getStats()

    local res = {}
    if (ifstats ~= nil) then
        local uptime = ntop.getUptime()
        local prefs = ntop.getPrefs()

        -- Round up
        local hosts_pctg = math.floor(1 + ((ifstats.stats.hosts * 100) / prefs.max_num_hosts))
        local flows_pctg = math.floor(1 + ((ifstats.stats.flows * 100) / prefs.max_num_flows))
        local macs_pctg = math.floor(1 + ((ifstats.stats.current_macs * 100) / prefs.max_num_hosts))

        res["ifid"] = ifid
        res["ifname"] = interface_name
        res["drops"] = ifstats.stats_since_reset.drops

        res["throughput_bps"] = ifstats.stats.throughput_bps;
        if (vs_utils.is_available()) then
            local total, total_in_progress = vs_utils.check_in_progress_status()
            res["vs_in_progress"] = total_in_progress or 0
        end
        if prefs.is_dump_flows_enabled == true then
            res["flow_export_drops"] = ifstats.stats_since_reset.flow_export_drops
            res["flow_export_count"] = ifstats.stats_since_reset.flow_export_count
        end

        if auth.has_capability(auth.capabilities.alerts) then
            res["engaged_alerts"] = ifstats["num_alerts_engaged"] or 0
            res["engaged_alerts_warning"] = ifstats["num_alerts_engaged_by_severity"]["warning"]
            res["engaged_alerts_error"] = ifstats["num_alerts_engaged_by_severity"]["error"]

            res["alerted_flows"] = ifstats["num_alerted_flows"] or 0
            res["alerted_flows_warning"] = ifstats["num_alerted_flows_warning"] or 0
            res["alerted_flows_error"] = ifstats["num_alerted_flows_error"] or 0
        end

        if periodic_activities_utils.have_degraded_performance() then
            res["degraded_performance"] = true
        end

        if not userHasRestrictions() then
            res["num_flows"] = ifstats.stats.flows
            res["num_hosts"] = ifstats.stats.hosts
            res["num_local_hosts"] = ifstats.stats.local_hosts
            res["num_devices"] = ifstats.stats.devices
            res["num_rcvd_only_hosts"] = ifstats.stats.hosts_rcvd_only
            res["num_local_rcvd_only_hosts"] = ifstats.stats.local_rcvd_only_hosts
        else
            res["num_hosts"] = countHosts().hosts
            res["num_local_hosts"] = countHosts().local_hosts
        end

        if ifstats.zmqRecvStats_since_reset then
            res["dropped_zmq_msg"] = ifstats.zmqRecvStats_since_reset.zmq_msg_drops
            res["dropped_flows"] = ifstats.zmqRecvStats_since_reset.dropped_flows
        end

        res["epoch"] = os.time()
        res["localtime"] = os.date("%H:%M:%S %z", res["epoch"])
        res["uptime"] = secondsToTime(uptime)
        res["uptime_sec"] = uptime
        if ntop.isPro() then
            local product_info = ntop.getInfo(true)

            if product_info["pro.out_of_maintenance"] then
                res["out_of_maintenance"] = true
            end

            if (product_info.ntopcloud) then
                res["ntopcloud"] = true
            end
        end

        res["hosts_pctg"] = hosts_pctg
        res["flows_pctg"] = flows_pctg
        res["macs_pctg"] = macs_pctg

        if isAdministrator() then
            res["num_live_captures"] = ifstats.stats.num_live_captures
        end

        local ingress_thpt = ifstats["eth"]["ingress"]["throughput"]
        local egress_thpt = ifstats["eth"]["egress"]["throughput"]
        res["throughput"] = {
            download = ingress_thpt["bps"],
            upload = egress_thpt["bps"]
        }

        if recording_utils.isAvailable() then
            if recording_utils.isEnabled(ifstats.id) then
                if recording_utils.isActive(ifstats.id) then
                    res["traffic_recording"] = "recording"
                else
                    res["traffic_recording"] = "failed"
                end
            end

            if recording_utils.isEnabled(ifstats.id) then
                local jobs_info = recording_utils.extractionJobsInfo(ifstats.id)
                if jobs_info.ready > 0 then
                    res["traffic_extraction"] = "ready"
                elseif jobs_info.total > 0 then
                    res["traffic_extraction"] = jobs_info.total
                end

                res["traffic_extraction_num_tasks"] = jobs_info.total
            end
        end

        -- Adding a preference if active discovery is enabled
        res["active_discovery_active"] = ntop.getPref("ntopng.prefs.is_periodic_network_discovery_running.ifid_" ..
            interface.getId()) == "1"

        res["is_loading"] = ifstats.isLoading
    end

    return res
end

-- ###############################

if (iffilter == "all") then
    for cur_ifid, ifname in pairs(interface.getIfNames()) do
        -- ifid in the key must be a string or json.encode will think
        -- its a lua array and will look for integers starting at one
        res[cur_ifid .. ""] = dumpInterfaceStats(cur_ifid)
    end
elseif not isEmptyString(iffilter) then
    res = dumpInterfaceStats(iffilter)
else
    res = dumpInterfaceStats(ifid)
end

rest_utils.answer(rc, res)
