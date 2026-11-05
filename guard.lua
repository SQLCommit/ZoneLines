-- ImGui stack guard.

local Gd = {};

-- Always closed.
local ALWAYS = { Begin = 'End', BeginChild = 'EndChild', BeginDisabled = 'EndDisabled' };
-- Closed when true.
local WHEN = { BeginTable = 'EndTable', BeginTabBar = 'EndTabBar', BeginTabItem = 'EndTabItem', BeginCombo = 'EndCombo',
    BeginTooltip = 'EndTooltip', TreeNode = 'TreePop' };
local PUSH = { PushStyleColor = 'PopStyleColor', PushStyleVar = 'PopStyleVar', PushID = 'PopID', PushTextWrapPos = 'PopTextWrapPos' };
-- Pops with a count.
local COUNTED = { PopStyleColor = true, PopStyleVar = true };

function Gd.wrap(im)
    local stack, n = {}, 0;
    local g = setmetatable({}, { __index = im });
    local function pop(kind, c)
        c = c or 1;
        local i = n;
        while c > 0 and i > 0 do
            if stack[i] == kind then table.remove(stack, i); n = n - 1; c = c - 1; end
            i = i - 1;
        end
    end
    for name, close in pairs(ALWAYS) do
        g[name] = function(...) local r, r2 = im[name](...); n = n + 1; stack[n] = close; return r, r2; end
    end
    for name, close in pairs(WHEN) do
        g[name] = function(...)
            local r, r2 = im[name](...);
            if r ~= false and r ~= nil then n = n + 1; stack[n] = close; end
            return r, r2;
        end
    end
    for name, close in pairs(PUSH) do
        g[name] = function(...) im[name](...); n = n + 1; stack[n] = close; end
    end
    local closers = {};
    for _, t in ipairs({ ALWAYS, WHEN, PUSH }) do for _, close in pairs(t) do closers[close] = true; end end
    for close in pairs(closers) do
        if COUNTED[close] then
            g[close] = function(c) pop(close, c); return im[close](c or 1); end
        else
            g[close] = function(...) pop(close, 1); return im[close](...); end
        end
    end

    local ctl = {};
    function ctl.depth() return n; end
    -- Custom closer.
    function ctl.open(fn) n = n + 1; stack[n] = fn; end
    function ctl.close() if n > 0 and type(stack[n]) == 'function' then stack[n] = nil; n = n - 1; end end
    -- Close all, newest first.
    function ctl.unwind()
        while n > 0 do
            local k = stack[n];
            stack[n] = nil;
            n = n - 1;
            if type(k) == 'function' then pcall(k);
            elseif COUNTED[k] then pcall(im[k], 1);
            else pcall(im[k]); end
        end
    end
    return g, ctl;
end

return Gd;
