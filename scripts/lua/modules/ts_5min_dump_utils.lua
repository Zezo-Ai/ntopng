--
-- (C) 2019-24 - ntop.org
--
local dirs = ntop.getDirs()
package.path = dirs.installdir .. "/scripts/lua/modules/pools/?.lua;" .. package.path
package.path = dirs.installdir .. "/scripts/lua/modules/timeseries/schemas/?.lua;" .. package.path

require "ts_5min"
require "ntop_utils"
require "check_redis_prefs"
local ts_utils = require "ts_utils_core"

local ts_custom

if ntop.exists(dirs.installdir .. "/scripts/lua/modules/timeseries/custom/ts_5min_custom.lua") then
    package.path = dirs.installdir .. "/scripts/lua/modules/timeseries/custom/?.lua;" .. package.path

    ts_custom = require "ts_5min_custom"
end

-- Set to true to debug host timeseries points timestamps
local enable_debug = false

local dirs = ntop.getDirs()
local ts_dump = {}

-- ########################################################

function ts_dump.l2_device_update_categories_rrds(when, devicename, device, ifstats, verbose)
    -- nDPI Protocol CATEGORIES
    if not ifstats.isViewed and not ifstats.isView then
        for k, cat in pairs(device["ndpi_categories"] or {}) do
            ts_utils.append("mac:ndpi_categories", {
                ifid = ifstats.id,
                mac = devicename,
                category = k,
                bytes = cat["bytes"]
            }, when)
        end
    end
end

function ts_dump.l2_device_update_stats_rrds(when, devicename, device, ifstats, verbose)
    if not ifstats.isViewed and not ifstats.isView then
        ts_utils.append("mac:traffic", {
            ifid = ifstats.id,
            mac = devicename,
            bytes_sent = device["bytes.sent"],
            bytes_rcvd = device["bytes.rcvd"]
        }, when, verbose)

        ts_utils.append("mac:arp_rqst_sent_rcvd_rpls", {
            ifid = ifstats.id,
            mac = devicename,
            request_pkts_sent = device["arp_requests.sent"],
            reply_pkts_rcvd = device["arp_replies.rcvd"]
        }, when)
    end
end

-- ########################################################

function ts_dump.blacklist_update(when, verbose)
    local lists_utils = require("lists_utils")
    local lists = lists_utils.getCategoryLists()

    for list_name, v in pairs(lists) do
        local current_hits = v.status.num_hits.total
        if (current_hits > 0) then
            list_name = list_name:gsub("%s+", "_") -- replace space with underscore
            local num_hits = lists_utils.getHitsSinceLastUpdateAndUpdate(list_name, current_hits)
            ts_utils.append("blacklist_v2:hits", {
                ifid = getSystemInterfaceId(),
                blacklist_name = list_name,
                hits = num_hits
            }, when)
        end
    end
end

-- ########################################################

function ts_dump.asn_update_rrds(when, ifstats, verbose)
    local asn_info = interface.getASesInfo({
        detailsLevel = "higher"
    })

    for _, asn_stats in pairs(asn_info["ASes"]) do
        local asn = asn_stats["asn"]

        -- Save ASN bytes
        ts_utils.append("asn:traffic", {
            ifid = ifstats.id,
            asn = asn,
            bytes_sent = asn_stats["bytes.sent"],
            bytes_rcvd = asn_stats["bytes.rcvd"]
        }, when)

        ts_utils.append("asn:score", {
            ifid = ifstats.id,
            asn = asn,
            score = asn_stats["score"],
            scoreAsClient = asn_stats["score.as_client"],
            scoreAsServer = asn_stats["score.as_server"]
        }, when)

        ts_utils.append("asn:traffic_sent", {
            ifid = ifstats.id,
            asn = asn,
            bytes = asn_stats["bytes.sent"]
        }, when)

        ts_utils.append("asn:traffic_rcvd", {
            ifid = ifstats.id,
            asn = asn,
            bytes = asn_stats["bytes.rcvd"]
        }, when)
        -- Save ASN ndpi stats
        if asn_stats["ndpi"] ~= nil then
            for proto_name, proto_stats in pairs(asn_stats["ndpi"]) do
                ts_utils.append("asn:ndpi", {
                    ifid = ifstats.id,
                    asn = asn,
                    protocol = proto_name,
                    bytes_sent = proto_stats["bytes.sent"],
                    bytes_rcvd = proto_stats["bytes.rcvd"]
                }, when)
            end
        end

        -- Save ASN RTT stats
        if not ifstats.isViewed and not ifstats.isView then
            ts_utils.append("asn:rtt", {
                ifid = ifstats.id,
                asn = asn,
                millis_rtt = asn_stats["round_trip_time"]
            }, when)
        end

        -- Save ASN TCP stats
        if not ifstats.isSampledTraffic then
            ts_utils.append("asn:tcp_retransmissions", {
                ifid = ifstats.id,
                asn = asn,
                packets_sent = asn_stats["tcpPacketStats.sent"]["retransmissions"],
                packets_rcvd = asn_stats["tcpPacketStats.rcvd"]["retransmissions"]
            }, when)

            ts_utils.append("asn:tcp_out_of_order", {
                ifid = ifstats.id,
                asn = asn,
                packets_sent = asn_stats["tcpPacketStats.sent"]["out_of_order"],
                packets_rcvd = asn_stats["tcpPacketStats.rcvd"]["out_of_order"]
            }, when)

            ts_utils.append("asn:tcp_lost", {
                ifid = ifstats.id,
                asn = asn,
                packets_sent = asn_stats["tcpPacketStats.sent"]["lost"],
                packets_rcvd = asn_stats["tcpPacketStats.rcvd"]["lost"]
            }, when)

            ts_utils.append("asn:tcp_keep_alive", {
                ifid = ifstats.id,
                asn = asn,
                packets_sent = asn_stats["tcpPacketStats.sent"]["keep_alive"],
                packets_rcvd = asn_stats["tcpPacketStats.rcvd"]["keep_alive"]
            }, when)
        end
    end
end

-- ########################################################

function ts_dump.obs_point_update_rrds(when, ifstats, verbose, config)
    -- Update rrd
    local obs_points_info = interface.getObsPointsInfo({
        detailsLevel = "higher"
    })

    for _, obs_point_stats in pairs(obs_points_info["ObsPoints"]) do
        local obs_point = obs_point_stats["obs_point"]
        local to_remove = obs_point_stats["to_remove"]

        -- Remove rrd requested by users
        if to_remove == true then
            interface.deleteObsPoint(obs_point)
            ts_utils.delete("obs_point", {
                ifid = ifstats.id,
                obs_point = obs_point
            })
            goto continue
            -- Go to the next observation point
        end

        -- Save Observation Points stats
        ts_utils.append("obs_point:traffic", {
            ifid = ifstats.id,
            obs_point = obs_point,
            bytes_sent = obs_point_stats["bytes.sent"],
            bytes_rcvd = obs_point_stats["bytes.rcvd"]
        }, when)

        ts_utils.append("obs_point:score", {
            ifid = ifstats.id,
            obs_point = obs_point,
            score = obs_point_stats["score"],
            scoreAsClient = obs_point_stats["score.as_client"],
            scoreAsServer = obs_point_stats["score.as_server"]
        }, when)

        ts_utils.append("obs_point:traffic_sent", {
            ifid = ifstats.id,
            obs_point = obs_point,
            bytes = obs_point_stats["bytes.sent"]
        }, when)

        ts_utils.append("obs_point:traffic_rcvd", {
            ifid = ifstats.id,
            obs_point = obs_point,
            bytes = obs_point_stats["bytes.rcvd"]
        }, when)

        if config.interface_ndpi_timeseries_creation == "per_protocol" or config.interface_ndpi_timeseries_creation ==
            "both" then
            -- Save Observation Points ndpi stats
            if obs_point_stats["ndpi"] ~= nil then
                for proto_name, proto_stats in pairs(obs_point_stats["ndpi"]) do
                    ts_utils.append("obs_point:ndpi", {
                        ifid = ifstats.id,
                        obs_point = obs_point,
                        protocol = proto_name,
                        bytes_sent = proto_stats["bytes.sent"],
                        bytes_rcvd = proto_stats["bytes.rcvd"]
                    }, when)
                end
            end
        end

        ::continue::
    end
end

-- ########################################################

function ts_dump.country_update_rrds(when, ifstats, verbose)
    local countries_info = interface.getCountriesInfo({
        detailsLevel = "higher",
        sortColumn = "column_country"
    })

    for _, country_stats in pairs(countries_info["Countries"] or {}) do
        local country = country_stats.country

        ts_utils.append("country:traffic", {
            ifid = ifstats.id,
            country = country,
            bytes_ingress = country_stats["ingress"],
            bytes_egress = country_stats["egress"],
            bytes_inner = country_stats["inner"]
        }, when)

        ts_utils.append("country:score", {
            ifid = ifstats.id,
            country = country,
            score = country_stats["score"],
            scoreAsClient = country_stats["score.as_client"],
            scoreAsServer = country_stats["score.as_server"]
        }, when)
    end
end

-- ########################################################

function ts_dump.vlan_update_rrds(when, ifstats, verbose)
    local vlan_info = interface.getVLANsInfo()

    if (vlan_info ~= nil) and (vlan_info["VLANs"] ~= nil) then
        for _, vlan_stats in pairs(vlan_info["VLANs"]) do
            local vlan_id = vlan_stats["vlan_id"]

            ts_utils.append("vlan:traffic", {
                ifid = ifstats.id,
                vlan = vlan_id,
                bytes_sent = vlan_stats["bytes.sent"],
                bytes_rcvd = vlan_stats["bytes.rcvd"]
            }, when)

            ts_utils.append("vlan:score", {
                ifid = ifstats.id,
                vlan = vlan_id,
                score = vlan_stats["score"],
                scoreAsClient = vlan_stats["score.as_client"],
                scoreAsServer = vlan_stats["score.as_server"]
            }, when)

            -- Save VLAN ndpi stats
            if vlan_stats["ndpi"] ~= nil then
                for proto_name, proto_stats in pairs(vlan_stats["ndpi"]) do
                    ts_utils.append("vlan:ndpi", {
                        ifid = ifstats.id,
                        vlan = vlan_id,
                        protocol = proto_name,
                        bytes_sent = proto_stats["bytes.sent"],
                        bytes_rcvd = proto_stats["bytes.rcvd"]
                    }, when)
                end
            end
        end
    end
end

-- ########################################################

function ts_dump.host_update_stats_rrds(when, hostname, host, ifstats, verbose)
    local l4_protocol_list = require "l4_protocol_list"
    -- Number of alerted flows
    ts_utils.append("host:alerted_flows", {
        ifid = ifstats.id,
        host = hostname,
        flows_as_client = host["alerted_flows.as_client"],
        flows_as_server = host["alerted_flows.as_server"]
    }, when)

    -- Number of unreachable flows
    ts_utils.append("host:unreachable_flows", {
        ifid = ifstats.id,
        host = hostname,
        flows_as_client = host["unreachable_flows.as_client"],
        flows_as_server = host["unreachable_flows.as_server"]
    }, when)

    -- Number of host unreachable flows
    ts_utils.append("host:host_unreachable_flows", {
        ifid = ifstats.id,
        host = hostname,
        flows_as_server = host["host_unreachable_flows.as_server"],
        flows_as_client = host["host_unreachable_flows.as_client"]
    }, when)

    -- Number of host TCP unidirectional flows
    if (host.num_unidirectional_tcp_flows ~= nil) then
        ts_utils.append("host:host_tcp_unidirectional_flows", {
            ifid = ifstats.id,
            host = hostname,
            flows_as_server = host.num_unidirectional_tcp_flows.num_ingress,
            flows_as_client = host.num_unidirectional_tcp_flows.num_egress
        }, when)
    end

    -- Number of dns packets sent
    ts_utils.append("host:dns_qry_sent_rsp_rcvd", {
        ifid = ifstats.id,
        host = hostname,
        queries_pkts = host["dns"]["sent"]["num_queries"],
        replies_ok_pkts = host["dns"]["rcvd"]["num_replies_ok"],
        replies_error_pkts = host["dns"]["rcvd"]["num_replies_error"]
    }, when)

    -- Number of dns packets rcvd
    ts_utils.append("host:dns_qry_rcvd_rsp_sent", {
        ifid = ifstats.id,
        host = hostname,
        queries_pkts = host["dns"]["rcvd"]["num_queries"],
        replies_ok_pkts = host["dns"]["sent"]["num_replies_ok"],
        replies_error_pkts = host["dns"]["sent"]["num_replies_error"]
    }, when)

    if (host["icmp.echo_pkts_sent"] ~= nil) then
        ts_utils.append("host:echo_packets", {
            ifid = ifstats.id,
            host = hostname,
            packets_sent = host["icmp.echo_pkts_sent"],
            packets_rcvd = host["icmp.echo_pkts_rcvd"]
        }, when)
    end

    if (host["icmp.echo_reply_pkts_sent"] ~= nil) then
        ts_utils.append("host:echo_reply_packets", {
            ifid = ifstats.id,
            host = hostname,
            packets_sent = host["icmp.echo_reply_pkts_sent"],
            packets_rcvd = host["icmp.echo_reply_pkts_rcvd"]
        }, when)
    end

    -- Number of udp packets
    ts_utils.append("host:udp_pkts", {
        ifid = ifstats.id,
        host = hostname,
        packets_sent = host["udp.packets.sent"],
        packets_rcvd = host["udp.packets.rcvd"]
    }, when)

    -- Tcp RX Stats
    ts_utils.append("host:tcp_rx_stats", {
        ifid = ifstats.id,
        host = hostname,
        retran_pkts = host["tcpPacketStats.rcvd"]["retransmissions"],
        out_of_order_pkts = host["tcpPacketStats.rcvd"]["out_of_order"],
        lost_packets = host["tcpPacketStats.rcvd"]["lost"]
    }, when)

    -- Tcp TX Stats
    ts_utils.append("host:tcp_tx_stats", {
        ifid = ifstats.id,
        host = hostname,
        retran_pkts = host["tcpPacketStats.sent"]["retransmissions"],
        out_of_order_pkts = host["tcpPacketStats.sent"]["out_of_order"],
        lost_packets = host["tcpPacketStats.sent"]["lost"]
    }, when)

    -- Number of TCP packets
    ts_utils.append("host:tcp_packets", {
        ifid = ifstats.id,
        host = hostname,
        packets_sent = host["tcp.packets.sent"],
        packets_rcvd = host["tcp.packets.rcvd"]
    }, when)

    -- Contacts
    if host["contacts.as_client"] then
        ts_utils.append("host:contacts", {
            ifid = ifstats.id,
            host = hostname,
            num_as_client = host["contacts.as_client"],
            num_as_server = host["contacts.as_server"]
        }, when)
    end

    if enable_debug then
        io.write(hostname .. "\n")
    end

    if (host.num_blacklisted_flows ~= nil) then
        -- Note: tot_as_* are never resetted, instead the other counters can be resetted
        ts_utils.append("host:num_blacklisted_flows", {
            ifid = ifstats.id,
            host = hostname,
            flows_as_client = host.num_blacklisted_flows.tot_as_client,
            flows_as_server = host.num_blacklisted_flows.tot_as_server
        }, when)
    end

    if ntop.isPro() then
        -- Contacted Hosts Behaviour
        if host["contacted_hosts_behaviour"] then
            if (host.contacted_hosts_behaviour.value > 0) then
                local lower = host.contacted_hosts_behaviour.lower_bound
                local upper = host.contacted_hosts_behaviour.upper_bound
                local value = host.contacted_hosts_behaviour.value
                local initialRun

                if (not (initialRun) and ((value < lower) or (value > upper))) then
                    rsp = "ANOMALY"
                else
                    rsp = "OK"
                end
            end

            ts_utils.append("host:contacts_behaviour", {
                ifid = ifstats.id,
                host = hostname,
                value = (host.contacted_hosts_behaviour.value or 0),
                lower_bound = (host.contacted_hosts_behaviour.lower_bound or 0),
                upper_bound = (host.contacted_hosts_behaviour.upper_bound or 0)
            }, when)
        end

        -- Active Flows Behaviour
        if host["active_flows_behaviour"] then
            local h = host["active_flows_behaviour"]

            -- tprint(h)
            ts_utils.append("host:cli_active_flows_behaviour", {
                ifid = ifstats.id,
                host = hostname,
                value = h["as_client"]["value"],
                lower_bound = h["as_client"]["lower_bound"],
                upper_bound = h["as_client"]["upper_bound"]
            }, when)
            ts_utils.append("host:srv_active_flows_behaviour", {
                ifid = ifstats.id,
                host = hostname,
                value = h["as_server"]["value"],
                lower_bound = h["as_server"]["lower_bound"],
                upper_bound = h["as_server"]["upper_bound"]
            }, when)

            -- Active Flows Anomalies
            local cli_anomaly = 0
            local srv_anomaly = 0
            if h["as_client"]["anomaly"] == true then
                cli_anomaly = 1
            end
            if h["as_server"]["anomaly"] == true then
                srv_anomaly = 1
            end

            ts_utils.append("host:cli_active_flows_anomalies", {
                ifid = ifstats.id,
                host = hostname,
                anomaly = cli_anomaly
            }, when)

            ts_utils.append("host:srv_active_flows_anomalies", {
                ifid = ifstats.id,
                host = hostname,
                anomaly = srv_anomaly
            }, when)
        end
    end

    -- L4 Protocols
    for id, _ in pairs(l4_protocol_list.l4_keys) do
        local k = l4_protocol_list.l4_keys[id][2]
        if ((host[k .. ".bytes.sent"] ~= nil) and (host[k .. ".bytes.rcvd"] ~= nil)) then
            ts_utils.append("host:l4protos", {
                ifid = ifstats.id,
                host = hostname,
                l4proto = tostring(k),
                bytes_sent = host[k .. ".bytes.sent"],
                bytes_rcvd = host[k .. ".bytes.rcvd"]
            }, when)
        else
            -- L2 host
            -- io.write("Discarding "..k.."@"..hostname.."\n")
        end
    end

    -- DSCP Classes
    for id, value in pairs(host.dscp) do
        if value["bytes.sent"] ~= nil and value["bytes.rcvd"] ~= nil then
            ts_utils.append("host:dscp", {
                ifid = ifstats.id,
                host = hostname,
                dscp_class = id,
                bytes_sent = value["bytes.sent"],
                bytes_rcvd = value["bytes.rcvd"]
            }, when)
        end
    end

    -- UDP breakdown
    ts_utils.append("host:udp_sent_unicast", {
        ifid = ifstats.id,
        host = hostname,
        bytes_sent_unicast = host["udpBytesSent.unicast"],
        bytes_sent_non_uni = host["udpBytesSent.non_unicast"]
    }, when)

    -- create custom rrds
    if ts_custom and ts_custom.host_update_stats then
        ts_custom.host_update_stats(when, hostname, host, ifstats, verbose)
    end
end

function ts_dump.host_update_ndpi_rrds(when, hostname, host, ifstats, verbose, config)
    -- nDPI Protocols
    for k, value in pairs(host["ndpi"] or {}) do
        local sep = string.find(value, "|")
        local sep2 = string.find(value, "|", sep + 1)
        local bytes_sent = string.sub(value, 1, sep - 1)
        local bytes_rcvd = string.sub(value, sep + 1, sep2 - 1)

        ts_utils.append("host:ndpi", {
            ifid = ifstats.id,
            host = hostname,
            protocol = k,
            bytes_sent = bytes_sent,
            bytes_rcvd = bytes_rcvd
        }, when)

        if config.ndpi_flows_timeseries_creation == "1" then
            local num_flows = string.sub(value, sep2 + 1)

            ts_utils.append("host:ndpi_flows", {
                ifid = ifstats.id,
                host = hostname,
                protocol = k,
                num_flows = num_flows
            }, when)
        end
    end
end

function ts_dump.host_update_categories_rrds(when, hostname, host, ifstats, verbose)
    -- nDPI Protocol CATEGORIES
    for k, value in pairs(host["ndpi_categories"] or {}) do
        local sep = string.find(value, "|")
        local bytes_sent = string.sub(value, 1, sep - 1)
        local bytes_rcvd = string.sub(value, sep + 1)

        ts_utils.append("host:ndpi_categories", {
            ifid = ifstats.id,
            host = hostname,
            category = k,
            bytes_sent = bytes_sent,
            bytes_rcvd = bytes_rcvd
        }, when)
    end
end

-- ########################################################

function ts_dump.light_host_update_rrd(when, hostname, host, ifstats, verbose)
    -- Traffic stats
    ts_utils.append("host:traffic", {
        ifid = ifstats.id,
        host = hostname,
        bytes_sent = host["bytes.sent"],
        bytes_rcvd = host["bytes.rcvd"]
    }, when)

    -- Score
    ts_utils.append("host:score", {
        ifid = ifstats.id,
        host = hostname,
        score_as_cli = host["score.as_client"],
        score_as_srv = host["score.as_server"]
    }, when)

    -- Total number of alerts
    ts_utils.append("host:total_alerts", {
        ifid = ifstats.id,
        host = hostname,
        alerts = host["total_alerts"]
    }, when)

    -- Engaged alerts
    if host["engaged_alerts"] then
        ts_utils.append("host:engaged_alerts", {
            ifid = ifstats.id,
            host = hostname,
            alerts = host["engaged_alerts"]
        }, when)
    end

    -- Number of flows
    if (host["active_flows.as_client"] or host["active_flows.as_server"]) then
        ts_utils.append("host:active_flows", {
            ifid = ifstats.id,
            host = hostname,
            flows_as_client = host["active_flows.as_client"] or 0,
            flows_as_server = host["active_flows.as_server"] or 0
        }, when)
    end

    ts_utils.append("host:total_flows", {
        ifid = ifstats.id,
        host = hostname,
        flows_as_client = host["total_flows.as_client"],
        flows_as_server = host["total_flows.as_server"]
    }, when)
end

-- ########################################################

function ts_dump.sflow_device_update_rrds(when, ifstats, verbose)
    local flowdevs = interface.getSFlowDevices()

    -- Return in case of view interface, no timeseries for view interface,
    -- already on the viewed interface.
    if ifstats.isView then
        return
    end

    for interface_id, device_list in pairs(flowdevs or {}) do
       for flow_device_ip, _value in pairs(device_list, asc) do
            local ports = interface.getSFlowDeviceInfo(flow_device_ip)

            if (verbose) then
                print("[" .. __FILE__() .. ":" .. __LINE__() .. "] Processing sFlow probe " .. flow_device_ip .. "\n")
            end

            for port_idx, port_value in pairs(ports) do
                if ifstats.has_seen_ebpf_events then
                    -- This is actualy an event exporter
                    local dev_ifname = format_utils.formatExporterInterface(port_idx, port_value)
                    ts_utils.append("evexporter_iface:traffic", {
                        ifid = ifstats.id,
                        exporter = flow_device_ip,
                        ifname = dev_ifname,
                        bytes_sent = port_value.ifOutOctets,
                        bytes_rcvd = port_value.ifInOctets
                    }, when)
                else
                    ts_utils.append("sflowdev_port:traffic", {
                        ifid = ifstats.id,
                        device = flow_device_ip,
                        port = port_idx,
                        bytes_sent = port_value.ifOutOctets,
                        bytes_rcvd = port_value.ifInOctets
                    }, when)
                end
            end
        end
    end
end

-- ########################################################

function ts_dump.host_update_rrd(when, hostname, host, ifstats, verbose, config)
    -- Crunch additional stats for local hosts only
    if config.host_ts_creation ~= "off" then
        if enable_debug then
            traceError(TRACE_NORMAL, TRACE_CONSOLE, "@" .. when .. " Going to update host " .. hostname)
        end

        ------ Light stats ------

        ts_dump.light_host_update_rrd(when, hostname, host, ifstats, verbose)

        ------------------------

        ------ Full Stats ------

        if (config.host_ts_creation == "full") then
            ts_dump.host_update_stats_rrds(when, hostname, host, ifstats, verbose)

            if (config.host_ndpi_timeseries_creation == "per_protocol" or config.host_ndpi_timeseries_creation == "both") then
                ts_dump.host_update_ndpi_rrds(when, hostname, host, ifstats, verbose, config)
            end

            if (config.host_ndpi_timeseries_creation == "per_category" or config.host_ndpi_timeseries_creation == "both") then
                ts_dump.host_update_categories_rrds(when, hostname, host, ifstats, verbose)
            end
        end
    end
end

-- ########################################################

function ts_custom_host_function(when, ifstats, hostname, host_ts)
    -- do nothing
end

-- ########################################################

local function read_file(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then
        return nil
    end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

-- ########################################################

local function local_custom_timeseries_dump_callback()
    local base_dir_file = dirs.installdir .. "/scripts/lua/modules/timeseries"
    local custom_file = "ts_custom_function"
    local lists_custom_file = base_dir_file .. "/" .. custom_file .. ".lua"

    if ntop.exists(lists_custom_file) then
        traceError(TRACE_INFO, TRACE_CONSOLE, "Loading " .. lists_custom_file)
        local content = read_file(lists_custom_file)

        -- tprint(content)

        local rc = load(content)

        rc("", "") -- needed to activate the function
        -- lua.execute(open(lists_custom_file).read())
    else
        traceError(TRACE_INFO, TRACE_CONSOLE, "Missing file " .. lists_custom_file)
    end
end

-- ########################################################

--
-- NOTE: this is executed every minute if ts_utils.hasHighResolutionTs() is true
--
-- See scripts/callbacks/minute/interface/timeseries.lua
--

function ts_dump.run_5min_dump(_ifname, ifstats, when, verbose)
    local profiling = require "profiling"
    local callback_utils = require "callback_utils"
    local config = get5MinTSConfig()
    local num_processed_hosts = 0
    local min_instant = when - (when % 60) - 60
    local dump_tstart = os.time()
    local dumped_hosts = {}

    -- load custom functions
    local_custom_timeseries_dump_callback()

    -- Save hosts stats (if enabled from the preferences)
    if config.host_ts_creation ~= "off" then
        local is_one_way_hosts_rrd_creation_enabled =
            (ntop.getPref("ntopng.prefs.hosts_one_way_traffic_rrd_creation") == "1")

        local in_time = callback_utils.foreachLocalTimeseriesHost(_ifname, true --[[ timeseries ]] ,
            is_one_way_hosts_rrd_creation_enabled, function(hostname, host_ts)
                local host_key = host_ts.tskey

                if (dumped_hosts[host_key] == nil) then
                    if (host_ts.initial_point ~= nil) then
                        -- Dump the first point
                        if enable_debug then
                            traceError(TRACE_NORMAL, TRACE_CONSOLE, "Dumping initial point for " .. host_key)
                        end

                        ts_dump.host_update_rrd(host_ts.initial_point_time, host_key, host_ts.initial_point, ifstats,
                            verbose, config)
                    end

                    ts_dump.host_update_rrd(when, host_key, host_ts.ts_point, ifstats, verbose, config)

                    -- mark the host as dumped
                    dumped_hosts[host_key] = true
                end

                ts_custom_host_function(min_instant, ifstats, hostname, host_ts)

                if ((num_processed_hosts % 64) == 0) then
                    if not ntop.isDeadlineApproaching() then
                        local num_local = interface.getNumLocalHosts() -- note: may be changed

                        interface.setPeriodicActivityProgress(num_processed_hosts * 100 / num_local)
                    end
                end

                num_processed_hosts = num_processed_hosts + 1
            end)

        if not in_time then
            traceError(TRACE_ERROR, TRACE_CONSOLE, "[" .. _ifname .. "]" .. i18n("error_rrd_cannot_complete_dump"))
            return false
        end

        if (in_time and (not ntop.isDeadlineApproaching())) then
            -- Here we assume that all the writes have completed successfully
            interface.setPeriodicActivityProgress(100)
        end
    end

    -- tprint("Dump of ".. num_processed_hosts .. " hosts: completed in " .. (os.time() - dump_tstart) .. " seconds")

    if config.l2_device_rrd_creation ~= "0" then
        local in_time = callback_utils.foreachDevice(_ifname, function(devicename, device)
            ts_dump.l2_device_update_stats_rrds(when, devicename, device, ifstats, verbose)

            if config.l2_device_ndpi_timeseries_creation == "per_category" then
                ts_dump.l2_device_update_categories_rrds(when, devicename, device, ifstats, verbose)
            end
        end)

        if not in_time then
            traceError(TRACE_ERROR, TRACE_CONSOLE, i18n("error_rrd_cannot_complete_dump"))
            return false
        end
    end

    -- create RRD for ASN
    if config.asn_rrd_creation == "1" then
        ts_dump.asn_update_rrds(when, ifstats, verbose)
    end

    -- create RRD for Observation Points
    if config.obs_point_rrd_creation == "1" then
        ts_dump.obs_point_update_rrds(when, ifstats, verbose, config)
    end

    -- create RRD for Countries
    if config.country_rrd_creation == "1" then
        ts_dump.country_update_rrds(when, ifstats, verbose)
    end

    -- Create RRD for vlans
    if config.vlan_rrd_creation == "1" then
        ts_dump.vlan_update_rrds(when, ifstats, verbose)
    end

    -- Create RRDs for flow and sFlow probes
    if (config.flow_devices_rrd_creation == "1" and ntop.isEnterpriseM() and not highExporterTimeseriesResolution()) then
        package.path = dirs.installdir .. "/scripts/lua/pro/modules/timeseries/callbacks/?.lua;" .. package.path
        local exporters_timeseries = require "exporters_timeseries"
        exporters_timeseries.update_timeseries(when, ifstats, verbose, false)
        -- Create RRDs for sflow counters
        ts_dump.sflow_device_update_rrds(when, ifstats, verbose)
    end

    -- Save Host Pools stats every 5 minutes
    if ((ntop.isPro()) and (tostring(config.host_pools_rrd_creation) == "1")) then
        local host_pools = require "host_pools"
        local host_pools_instance = host_pools:create()

        host_pools_instance:updateRRDs(ifstats.id, true --[[ also dump nDPI data ]] , verbose, when)
    end
end

-- ########################################################

return ts_dump
