--[[
  Snippet (and module) that provides safe_require function:

  safe_require will attempt to load (require) one or several modules and will return the following:
    if any of the modules failed it will return false (won't raise an error)
    if all of them were loaded successfully, the value returned by require for the first module

  if you need access to any of the modules, you need to access the table required[moduleName],
  the table 'required' is returned when you require this module

  Author: Jose Maria Perez Ramos <jose.m.perez.ramos+git gmail>
  Date: 2015.12.01
  Version: 1.0.0
  This micro code snippet is public-domain
]]

local required = {}

local function _safe_require(moduleName)
  local ok, ret = pcall(function()
    required[moduleName] = require(moduleName)
    return required[moduleName]
  end)
  return ok and ret
end

function safe_require(moduleName, ...)
  return not moduleName or (safe_require(...) and _safe_require(moduleName))
end

return required, safe_require

