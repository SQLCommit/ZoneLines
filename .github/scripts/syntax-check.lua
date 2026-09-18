-- Compiles every Lua file named on the command line, without running any of it, and lists the ones that fail.
-- Used by Prepare release (.github/workflows/prepare-release.yml). Exit code 1 when any file has a syntax error.
local bad = 0
for i = 1, #arg do
    local chunk, err = loadfile(arg[i])
    if not chunk then
        io.stderr:write(err, '\n')
        bad = bad + 1
    end
end
if bad > 0 then
    io.stderr:write(('%d of %d Lua files do not compile\n'):format(bad, #arg))
    os.exit(1)
end
print(('%d Lua files compile'):format(#arg))
