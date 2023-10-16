--[[
########################################################
KumoMTA Smart Sink and Reflector policy
This config policy defines KumoMTA as a smart sink and 
reflector to simulate realworld delivery testing.
It will consume and process all incoming messages in the
following ways:
 - incomming mail will be evalueated against the behaviour 
    file at behave.toml
 - mail will be bounced (5xx), Deferred (4xx), or accepted (250) 
    based on the percentages in that file per domain 
 - TBD: will add oob and fbl responses in the future
 - TBD: might add opens and clicks in the future

Sample behave.toml file: 
[yahoo.com]
  bounce 20
  defer  20
  # all remailing will be accepted and dropped
  

########################################################
]]--

local mod = {}
local kumo = require 'kumo'
local utils = require 'policy-extras.policy_utils'
local shaping = require 'policy-extras.shaping'

local shaper = shaping:setup_with_automation {
  publish = { 'http://127.0.0.1:8008' },
  subscribe = { 'http://127.0.0.1:8008' },
}

--[[ ================================================================================== ]]--
-- CALLED ON STARTUP, ALL ENTRIES WITHIN init REQUIRE A SERVER RESTART WHEN CHANGED.
kumo.on('init', function()

  -- For debugging only
  kumo.set_diagnostic_log_filter 'kumod=debug'

  -- Configure publishing of logs to automation daemon
  shaper.setup_publish()

-----------------------------------------------------
--[[ Define the Spool ]]--
-----------------------------------------------------
  kumo.define_spool {
    name = 'data',
    path = '/var/spool/kumomta/data',
    kind = 'RocksDB',
  }

  kumo.define_spool {
    name = 'meta',
    path = '/var/spool/kumomta/meta',
    kind = 'RocksDB',
  }
-----------------------------------------------------
--[[ Define logging parameters ]]--
-----------------------------------------------------
-- for local logs
  kumo.configure_local_logs {
    log_dir = '/var/log/kumomta',
    max_segment_duration = '60 minutes',
}

-----------------------------------------------------
--[[ Configure Bounce Classifier ]]--
-----------------------------------------------------
  kumo.configure_bounce_classifier {
    files = {
      '/opt/kumomta/share/bounce_classifier/iana.toml',
    },
  }

-----------------------------------------------------
--[[ Configure listeners ]]--
-----------------------------------------------------
--for HTTP(s)
  kumo.start_http_listener {
    listen = '0.0.0.0:8000',
    -- allowed to access any http endpoint without additional auth
    trusted_hosts = { '127.0.0.1', '::1'},
  }

-- for SMTP on port 25,26
  for _, port in ipairs { 25, 2025, 587 } do
    kumo.start_esmtp_listener {
      listen = '0:' .. tostring(port),
      banner = "KumoMTA Sink Server and Reflector.",
    }
  end


----------------------------------------------------------------------------
end) -- END OF THE INIT EVENT
----------------------------------------------------------------------------

-- Called to validate the helo and/or ehlo domain
kumo.on('smtp_server_ehlo', function(domain)
  print ("NOTICE>> SMTP Listener hit FROM:" .. domain )
end)


-- Cache config files for 1 hour
  cached_toml_load = kumo.memoize(kumo.toml_load,{name='cache-toml-files-for-1-hour', ttl='1 hour', capacity = 100,})

-- Get the domains configuration
  local listener_domains = require 'policy-extras.listener_domains'
  kumo.on('get_listener_domain', listener_domains:setup({'/opt/kumomta/etc/policy/listener_domains.toml'}))

--[[ ================================================================================== ]]--
--          Load important globals here
--[[ ================================================================================== ]]--


-----------------------------------------------------
--[[ Define IP Egress Sources and Pools ]]--
-------------------------------------------------------
-- use the sources helper to configure IPs and Pools in one file
local sources = require 'policy-extras.sources'
sources:setup { '/opt/kumomta/etc/policy/egress_sources.toml' }

----------------------------------------------------------------------------
--[[ Traffic Shaping Automation Helper (TSA) ]]--
----------------------------------------------------------------------------
local shaping = require 'policy-extras.shaping'
local shaping_config = '/opt/kumomta/etc/policy/shaping.toml'
local get_shaping_config = shaping:setup({shaping_config})
local get_shaping_config = shaping:setup()

----------------------------------------------------------------------------
--[[ Determine queue routing ]]--
----------------------------------------------------------------------------
-- Attach various hooks to the shaper
kumo.on('get_egress_path_config', shaper.get_egress_path_config)
kumo.on('should_enqueue_log_record', shaper.should_enqueue_log_record)
kumo.on('get_queue_config', function(domain, tenant, campaign)

  local cfg = shaper.get_queue_config(domain, tenant, campaign)
  if cfg then
    return cfg
  end

  local tenant_list = cached_toml_load("/opt/kumomta/etc/policy/tenant_list.toml")
  local params = {
    egress_pool = tenant_list.TENANT_TO_POOL[tenant],
  }
  utils.merge_into(tenant_list.TENANT_PARAMS[tenant] or {}, params)

  return kumo.make_queue_config(params)
end)

----------------------------------------------------------------------------
--[[ DKIM Signing function ]]--
----------------------------------------------------------------------------
local dkim_sign = require 'policy-extras.dkim_sign'
local dkim_signer = dkim_sign:setup({'/opt/kumomta/etc/policy/dkim_data.toml'})

----------------------------------------------------------------------------
--[[ Fake bounce reflector function ]]--
----------------------------------------------------------------------------
function bounce_sim(msg)
  print ("NOTICE>> Starting Bounce Simulation")
  local sim_result = "NotSet"
  local domain = msg:recipient().domain
  local fake_domain = string.match(domain,'-[a-z0-9]*') or "" -- assuming domain is in the format: not-yahoo.aasland.com
  if (fake_domain ~= "" and fake_domain ~= nil) then 
    fake_domain = string.gsub(fake_domain,"-","")
    fake_domain = fake_domain .. ".com"
  else
    print ("NOTICE>> invalid domain format for this server.  Sending to dev/null. " .. domain)
    msg:set_meta('queue','null')
  end

  local sqlite = require 'sqlite'
  local sqlitepath = "/opt/kumomta/etc/policy/fakebouncedata.db"
  local db = sqlite.open(sqlitepath)

--[[ get bounce codes for the current fake_domain ]]--
  local bounce_codes = db:execute('SELECT code, context FROM bounce_data WHERE domain = "' .. fake_domain .. '" AND code LIKE "5%"')
  local defer_codes = db:execute('SELECT code, context FROM bounce_data WHERE domain = "' .. fake_domain .. '" AND code LIKE "4%"')
  print ("NOTICE>> " .. fake_domain .. " has " .. #bounce_codes .. " bounce codes")

  -- Check to see if the current domain is in the list of big MBPs
  inMBPList = false
  BigMBPs = {'yahoo.com','outlook.com','hotmail.com','gmail.com','comcast.com','aol.com'}
  for _, v in pairs(BigMBPs) do
    if v == fake_domain then 
      inMBPList = true
    end
  end
  if inMBPList == false then
    fake_domain = "default"
  end

  local behave = kumo.toml_load("/opt/kumomta/etc/policy/behave.toml")
  if behave[fake_domain] ~= nil then
    print ("NOTICE>> Table exists in behaviour list")  

--check to see if there are any stored bounce codes for that domain - if not, skip it.
  if #bounce_codes > 1 then
    local bounce_val = math.random(#bounce_codes)
    local defer_val = math.random(#defer_codes)
    local bounce_rate = behave[fake_domain].bounce
    local defer_rate = behave[fake_domain].defer
    local defer_rate_m = 100-defer_rate
    local bounce_rate_m = 100-bounce_rate

    if bounce_rate <= defer_rate then
      lobad_rate = 'bounce_rate'
    else
      lobad_rate = 'defer_rate'
    end
    print ("Simulating domain " .. fake_domain .. "")
    print ("Bounce rate is " .. bounce_rate .. "")
    print ("Defer rate is " .. defer_rate .. "")
    print ("Lower value is " .. lobad_rate)


    -- Get a random number between 1 and 100
    -- if it is 0 to (lower-of-bounce-and-defer-rate) send bounce code
    -- if it is (higher-of-bounce-and-defer-rate) to 100 then send defer code
    -- if it fell through, send 250OK
    rnd_val = math.random(100)
    print ("Random value is " .. rnd_val)
    if lobad_rate == 'bounce_rate' then
      if rnd_val <= tonumber(bounce_rate) then
        -- look these up in future in a table
        sim_result = "Bounced"
	print ("Bounce_Val = " .. bounce_val)
	local res_code = bounce_codes[bounce_val].code
	local res_context = tostring(bounce_codes[bounce_val].context)
	print ("Bounce code = " .. res_code)
	print ("Bounce context = " .. res_context)
        kumo.reject(res_code,res_context)
      end
      if rnd_val >= tonumber(defer_rate_m) then
        sim_result = "Deferred"
        local res_code = defer_codes[defer_val].code
        local res_context = tostring(defer_codes[defer_val].context)
	print ("Deferal code = " .. res_code)
	print ("Deferal context = " .. res_context)
        kumo.reject(res_code,res_context)
      end
    else
      if rnd_val <= tonumber(defer_rate) then
        sim_result = "Deferred"
        local res_code = defer_codes[defer_val].code
        local res_context = tostring(defer_codes[defer_val].context)
	print ("Deferal code = " .. res_code)
	print ("Deferal context = " .. res_context)
        kumo.reject(res_code,res_context)
      end
      if rnd_val >= tonumber(bounce_rate_m) then
        sim_result = "Bounced"
	local res_code = bounce_codes[bounce_val].code
	local res_context = tostring(bounce_codes[bounce_val].context)
	print ("Bounce code = " .. res_code)
	print ("Bounce context = " .. res_context)
        kumo.reject(res_code,res_context)
      end
    end
  end

-- if you get here, the message will be accepted as "delivered"
    print ("Message was simulated as 'delivered' (to null)")
    sim_result = "Delivered"
    msg:set_meta('queue','null')
    print ("Simulation Processor Queue sent " .. domain .. " mail to null")


  end 

  return sim_result

 end

----------------------------------------------------------------------------
--[[ End of bounce reflector function ]]--
----------------------------------------------------------------------------

----------------------------------------------------------------------------
--[[ Determine what to do on SMTP message reception ]]--
----------------------------------------------------------------------------

kumo.on('smtp_server_message_received', function(msg)

  print ( "NOTICE>> incoming domain TO is " .. msg:recipient().domain )

-- Invoke the bounce simulator function
  local sim_result = bounce_sim(msg)
  print ("Message was simulated as " .. sim_result .. "\n")

end)

----------------------------------------------------------------------------
--[[ Determine what to do on HTTP message reception ]]--
----------------------------------------------------------------------------
kumo.on('http_message_generated', function(msg)

-- For now, set all messages to dev/null
  msg:set_meta('queue','null')

  print ("NOTICE>> HTTP Queue sent " .. domain .. " mail to null")

end)

----------------------------------------------------------------------------
--[[ End of KumoMTA Smart Sink and Reflector ]]--
----------------------------------------------------------------------------

