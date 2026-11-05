-- Effects drawn after the world.
local ffi     = require 'ffi';
local d3d8    = require 'd3d8';
local effects = require 'effects';
local signs   = require 'signs';
local textures = require 'textures';

local late = {};

-- Render states saved here.
local RS = { 7, 14, 15, 19, 20, 22, 23, 24, 25, 27, 28, 47, 137 };
local TSS0 = { 1, 2, 3, 4, 5, 6, 13, 14, 16, 17, 18 };
local TSS1 = { 1, 4 };
local rs_v, t0_v, t1_v = {}, {}, {};
for i = 1, #RS do rs_v[i] = 0; end
for i = 1, #TSS0 do t0_v[i] = 0; end
for i = 1, #TSS1 do t1_v[i] = 0; end

local out_dw  = ffi.new('DWORD[1]');
local out_s   = ffi.new('IDirect3DSurface8*[1]');
local out_tex = ffi.new('IDirect3DBaseTexture8*[1]');
local vp, save_vp = ffi.new('D3DVIEWPORT8'), ffi.new('D3DVIEWPORT8');
local view, proj = ffi.new('D3DMATRIX'), ffi.new('D3DMATRIX');
local s_world, s_view, s_proj = ffi.new('D3DMATRIX'), ffi.new('D3DMATRIX'), ffi.new('D3DMATRIX');
local identity = ffi.new('D3DMATRIX');
identity._11, identity._22, identity._33, identity._44 = 1, 1, 1, 1;

local rt, ds = nil, nil;   -- World target refs.
local world_w, world_h = 0, 0;
local armed, busy, registered, warned = false, false, false, false;

local function drop_refs()
    if (rt ~= nil) then rt.lpVtbl.Release(rt); rt = nil; end
    if (ds ~= nil) then ds.lpVtbl.Release(ds); ds = nil; end
end

local function draw(dev, vt)
    local cur_rt, cur_ds = nil, nil;
    if (vt.GetRenderTarget(dev, out_s) == 0) then cur_rt = out_s[0]; end
    if (vt.GetDepthStencilSurface(dev, out_s) == 0) then cur_ds = out_s[0]; end
    vt.GetViewport(dev, save_vp);
    local have_w = (vt.GetTransform(dev, 256, s_world) == 0);
    local have_v = (vt.GetTransform(dev, 2, s_view) == 0);
    local have_p = (vt.GetTransform(dev, 3, s_proj) == 0);
    for i = 1, #RS do rs_v[i] = (vt.GetRenderState(dev, RS[i], out_dw) == 0) and out_dw[0] or -1; end
    for i = 1, #TSS0 do t0_v[i] = (vt.GetTextureStageState(dev, 0, TSS0[i], out_dw) == 0) and out_dw[0] or -1; end
    for i = 1, #TSS1 do t1_v[i] = (vt.GetTextureStageState(dev, 1, TSS1[i], out_dw) == 0) and out_dw[0] or -1; end
    local fvf = (vt.GetVertexShader(dev, out_dw) == 0) and out_dw[0] or nil;
    local ps  = (vt.GetPixelShader(dev, out_dw) == 0) and out_dw[0] or nil;
    local tex = (vt.GetTexture(dev, 0, out_tex) == 0) and out_tex[0] or nil;

    local ok, err = true, nil;
    if (vt.SetRenderTarget(dev, rt, ds) == 0) then
        vt.SetTransform(dev, 256, identity);
        vt.SetTransform(dev, 2, view);
        vt.SetTransform(dev, 3, proj);
        vt.SetPixelShader(dev, 0);
        vt.SetRenderState(dev, 137, 0);   -- lighting
        vt.SetRenderState(dev, 28, 0);    -- fog
        vt.SetRenderState(dev, 22, 1);    -- cull none
        vt.SetRenderState(dev, 27, 1);    -- blend
        vt.SetRenderState(dev, 7, 1);     -- z test
        vt.SetRenderState(dev, 23, 4);    -- LESSEQUAL
        vt.SetRenderState(dev, 47, 0);    -- no bias
        effects.set_atest(0);
        ok, err = pcall(effects.flush, dev);
        if (ok) then ok, err = pcall(signs.flush, dev); else signs.discard(); end
    else
        effects.discard();
        signs.discard();
    end

    vt.SetRenderTarget(dev, cur_rt, cur_ds);
    vt.SetViewport(dev, save_vp);
    if (have_w) then vt.SetTransform(dev, 256, s_world); end
    if (have_v) then vt.SetTransform(dev, 2, s_view); end
    if (have_p) then vt.SetTransform(dev, 3, s_proj); end
    for i = 1, #RS do if (rs_v[i] ~= -1) then vt.SetRenderState(dev, RS[i], rs_v[i]); end end
    for i = 1, #TSS0 do if (t0_v[i] ~= -1) then vt.SetTextureStageState(dev, 0, TSS0[i], t0_v[i]); end end
    for i = 1, #TSS1 do if (t1_v[i] ~= -1) then vt.SetTextureStageState(dev, 1, TSS1[i], t1_v[i]); end end
    if (fvf ~= nil) then vt.SetVertexShader(dev, fvf); end
    if (ps ~= nil) then vt.SetPixelShader(dev, ps); end
    vt.SetTexture(dev, 0, tex);
    if (tex ~= nil) then tex.lpVtbl.Release(tex); end
    if (cur_rt ~= nil) then cur_rt.lpVtbl.Release(cur_rt); end
    if (cur_ds ~= nil) then cur_ds.lpVtbl.Release(cur_ds); end
    if (not ok and not warned) then warned = true; textures.log('late draw: ' .. tostring(err)); end
end

local function on_dpup()
    if (not armed or busy) then return; end
    local dev = d3d8.get_device();
    if (dev == nil) then return; end
    local vt = dev.lpVtbl;
    if (vt.GetViewport(dev, vp) ~= 0) then return; end
    if (vp.Width == world_w and vp.Height == world_h) then return; end   -- Still the world.
    armed, busy = false, true;
    draw(dev, vt);
    busy = false;
    drop_refs();
end

-- Hold target and camera.
function late.arm(dev)
    if (not effects.pending() and not signs.pending()) then signs.idle(); return; end
    if (armed) then late.cancel(); end
    local vt = dev.lpVtbl;
    if (vt.GetRenderTarget(dev, out_s) ~= 0) then effects.discard(); signs.discard(); return; end
    rt = out_s[0];
    if (vt.GetDepthStencilSurface(dev, out_s) ~= 0) then drop_refs(); effects.discard(); signs.discard(); return; end
    ds = out_s[0];
    if (vt.GetViewport(dev, vp) ~= 0 or vt.GetTransform(dev, 2, view) ~= 0 or vt.GetTransform(dev, 3, proj) ~= 0) then
        drop_refs(); effects.discard(); signs.discard(); return;
    end
    world_w, world_h = vp.Width, vp.Height;
    if (not registered) then
        ashita.events.register('d3d_dpup', 'zonelines_late', on_dpup);
        registered = true;
    end
    armed = true;
end

-- Drop undrawn effects.
function late.cancel()
    if (armed) then
        armed = false;
        effects.discard();
        signs.discard();
        if (not warned) then warned = true; textures.log('late draw: no back-buffer draw after the world pass'); end
    end
    drop_refs();
end

function late.release()
    late.cancel();
    if (registered) then ashita.events.unregister('d3d_dpup', 'zonelines_late'); registered = false; end
end

return late;
