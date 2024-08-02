--[[---------------------------]]--
-- k_helpers.lua
-- a collection of useful functions
-- to enhance KumoMTA
--[[---------------------------]]--
local name = "k_helpers"
local mod = { }
local kumo = require 'kumo'
local utils = require 'policy-extras.policy_utils'
local sqlite = require 'sqlite'


---------------------------------------------------------------------
-- Function create_webhook
-- used to create webhook constructors for KumoMTA
-- usage: create_webhook(name,target,user,pass,log_hooks)
-- expects a webhook endpoint using Basic Auth
-- name = webhook name to register
-- target = URL and Port for webhook collector
-- user = HTTP basic username
-- pass = HTTP basic password (unencrypted)
-- log_hooks = log_hooks (exactly as spelled)
---------------------------------------------------------------------
--
-- Note that it is probably better to use the Kumo built-in helper function for this
-- https://docs.kumomta.com/userguide/operation/webhooks/?h=webhook#using-the-log_hookslua-helper
--
function mod.create_webhook(wh_name,wh_target,basic_user,basic_pass,log_hooks)
 log_hooks:new {
   name = wh_name,
   constructor = function(domain, tenant, campaign)
    local connection = {}
    local client = kumo.http.build_client {}
    function connection:send(message)
      local response = client
        :post(wh_target)
        :header('Content-Type', 'application/json')
        :basic_auth(basic_user,basic_pass)
        :body(message:get_data())
        :send()


	print ("Shipping Webhook: " .. wh_name )

      local disposition = string.format(
        '%d %s: %s',
        response:status_code(),
        response:status_reason(),
        response:text()
      )
print ("Disposition : " .. disposition )

      if response:status_is_success() then
        return disposition
      end

      kumo.reject(500, disposition)
    end
    return connection
  end,
}
end

-------------------------------------------------------------  
-- sqlite_auth_checker
-- Used to check user and password credentials from a local sqlite db
-- db is expected to have two text fields called email and password
-- Note that the "email" field is just text with no format validation
-------------------------------------------------------------  
function mod.sqlite_auth_check(user, password)
    local db = sqlite.open '/home/myaccount/mypswd.db'
    local result = db:execute ('select * from users where email=? and password=?', user,password)

    -- if any rows are returned, it was because we found a match
    if #result == 1 then
      return true
    else
      return false
    end
  end


-- This function converts a string to base64
-- Note that it is porbably better to use the Kumo builting functions for this
-- https://docs.kumomta.com/reference/kumo.encode/base64_decode/
-- https://docs.kumomta.com/reference/kumo.encode/base64_encode/
--
function mod.to_base64(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r,b='',x:byte()
        for i=8,1,-1 do r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

-- this function converts base64 to string
function mod.from_base64(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end


-----------------------------------------------------------------------
--[[ Local Function printTableF() ]]--
-- Used to pretty print any sized table in Lua
-- but in this case it writes to an external file
-- This could be resource intensive so only use it for debugging
-------------------------------------------------------------------------
function mod.k_printTableF( filename, t )
    local fh = io.open(filename,"a")
    local printTable_cache = {}

    local function sub_printTable( t, indent, filename )

        if ( printTable_cache[tostring(t)] ) then
            fh:write( indent .. "*" .. tostring(t) )
            fh:write("\n")
        else
            printTable_cache[tostring(t)] = true
            if ( type( t ) == "table" ) then
                for pos,val in pairs( t ) do
                    if ( type(val) == "table" ) then
                        fh:write( indent .. "[" .. pos .. "] => " .. tostring( t ).. " {" )
                        fh:write("\n")
                        sub_printTable( val, indent .. string.rep( " ", string.len(pos)+8 ), filename )
                        fh:write( indent .. string.rep( " ", string.len(pos)+6 ) .. "}" )
                        fh:write("\n")
                elseif ( type(val) == "string" ) then
                        fh:write( indent .. "[" .. pos .. '] => "' .. val .. '"' )
                        fh:write("\n")
                    else
                        fh:write( indent .. "[" .. pos .. "] => " .. tostring(val) )
                        fh:write("\n")
                    end
                end
            else
                fh:write( indent..tostring(t) )
                fh:write("\n")
            end
        end
    end

    if ( type(t) == "table" ) then
        fh:write( tostring(t) .. " {" )
        fh:write("\n")
        sub_printTable( t, "  ", filename )
        fh:write( "}" )
        fh:write("\n")
    else
        sub_printTable( t, "  ",filename )
    end
    fh:write("\n")
    fh:close()

end

--[[ isempty() is a shortcut to eval if a variable is nill or no value ]]--
function mod.isempty(s)
    return s == nil or s == ''
end

--[[ Extract the x-tenant header value and assign it to the tenant variable ]]--
-- function set_tenant_by_X()
function mod.set_tenant_by_X(headername)
  local headers = message:get_all_headers()
  local tenant = "default"
  if headers[headername] == high then
    tenant = "priority"
  end
  return tenant
end


--[[ Print a text string to a local file ]]--
-- function k_print(fname,text)
function mod.k_print(fname,text)
  fh = io.open(fname,"a")
  fh:write(text)
  fh:close()
end


function mod.table_contains(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false

end

-----------------------------------------------------------------------------
--[[ Function to extract the actual email from a pretty-print email address ]]--

function mod.esanitize(in_val)
  local sos = 1
  local eos = #in_val
  local out_val = in_val:sub(sos,eos)
  sos, eos = string.find(in_val, "<.*>", 1, false)
  if sos ~= nil and sos >= 1 then
    out_val = string.sub(in_val,sos+1,eos-1)
  end
  
  return (out_val)	
end

-----------------------------------------------------------------------------


return mod
