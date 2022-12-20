
--- @class cc_term_lib
--- @field blit function
--- @field setCursorPos function

--------------------------------------------------------------------------------

local CH_SPACE = string.byte ' '
local CH_0 = string.byte '0'
local CH_A = string.byte 'a'
local BT_SUBPIXEL_NOISEY = string.char(149)
local ch_lookup_byte = {}
local ch_lookup_char = {}
local ch_lookup_subpixel = {}
local subpixel_code_ch_lookup = {}
local subpixel_code_fg_lookup = {}
local subpixel_code_bg_lookup = {}

for i = 0, 15 do
	ch_lookup_byte[2 ^ i] = i < 10 and CH_0 + i or CH_A + (i - 10)
	ch_lookup_char[2 ^ i] = string.char(ch_lookup_byte[2 ^ i])
end

local function subpixel_byte_value(v0, v1, v2, v3, v4, v5)
	local b0 = v0 == v5 and 0 or 1
	local b1 = v1 == v5 and 0 or 1
	local b2 = v2 == v5 and 0 or 1
	local b3 = v3 == v5 and 0 or 1
	local b4 = v4 == v5 and 0 or 1

	return 128 + b0 + b1 * 2 + b2 * 4 + b3 * 8 + b4 * 16
end

local function subpixel_char_value(v0, v1, v2, v3, v4, v5)
	return string.char(subpixel_byte_value(v0, v1, v2, v3, v4, v5))
end

local function eval_subpixel_lookups(ci0, ci1, ci2, ci3, ci4, ci5, subpixel_code)
	local colour_count = { [ci0] = 1 }
	local unique_colour_values = { ci0 }
	local unique_colours = 1

	for _, c in ipairs { ci1, ci2, ci3, ci4, ci5 } do
		if colour_count[c] then
			colour_count[c] = colour_count[c] + 1
		else
			colour_count[c] = 1
			unique_colours = unique_colours + 1
			unique_colour_values[unique_colours] = c
		end
	end

	table.sort(unique_colour_values, function(a, b)
		return colour_count[a] > colour_count[b]
	end)

	if unique_colours == 1 then -- these should never be used!
		subpixel_code_ch_lookup[subpixel_code] = false
		subpixel_code_fg_lookup[subpixel_code] = false
		subpixel_code_bg_lookup[subpixel_code] = false
		return
	end

	local colour_indices = { ci0, ci1, ci2, ci3, ci4, ci5 }
	local modal1_colour_index = unique_colour_values[1]
	local modal2_colour_index = unique_colour_values[2]
	local modal1_index = 0
	local modal2_index = 0

	for i = 1, 6 do
		if colour_indices[i] == modal1_colour_index then
			modal1_index = i
		end
		if colour_indices[i] == modal2_colour_index then
			modal2_index = i
		end
	end

	-- spatially map pixels!
	ci0 = (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or ci2
	ci1 = (ci1 == modal1_colour_index or ci1 == modal2_colour_index) and ci1 or (ci0 == modal1_colour_index or ci0 == modal2_colour_index) and ci0 or ci3
	ci2 = (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or ci4
	ci3 = (ci3 == modal1_colour_index or ci3 == modal2_colour_index) and ci3 or (ci2 == modal1_colour_index or ci2 == modal2_colour_index) and ci2 or ci5
	ci4 = (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or ci2
	ci5 = (ci5 == modal1_colour_index or ci5 == modal2_colour_index) and ci5 or (ci4 == modal1_colour_index or ci4 == modal2_colour_index) and ci4 or ci3

	subpixel_code_ch_lookup[subpixel_code] = subpixel_char_value(ci0, ci1, ci2, ci3, ci4, ci5)
	subpixel_code_fg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal2_index or modal1_index
	subpixel_code_bg_lookup[subpixel_code] = ci5 == modal1_colour_index and modal1_index or modal2_index
end

local subpixel_code = 0
for c5 = 0, 3 do
	for c4 = 0, 3 do
		for c3 = 0, 3 do
			for c2 = 0, 3 do
				for c1 = 0, 3 do
					for c0 = 0, 3 do
						eval_subpixel_lookups(c0, c1, c2, c3, c4, c5, subpixel_code)
						subpixel_code = subpixel_code + 1
					end
				end
			end
		end
	end
end

--- @class ccFramebuffer
--- @field width integer
--- @field height integer
--- @field front table
--- @field back table

--- @param width integer
--- @param height integer
--- @return ccFramebuffer
local function create_framebuffer(width, height)
	local fb = {}

	fb.width = width
	fb.height = height
	fb.front = {}
	fb.back = {}

	for i = 1, width * height do
		fb.front[i] = 1
		fb.back[i] = 1
	end

	return fb
end

--- @param width integer
--- @param height integer
--- @return ccFramebuffer
local function create_framebuffer_subpixel(width, height)
	return create_framebuffer(width * 2, height * 3) -- multiply by subpixel dimensions
end

--- @param fb ccFramebuffer
--- @param colour integer
local function clear_framebuffer(fb, colour)
	local fb_front = fb.front
	for i = 1, fb.width * fb.height do
		fb_front[i] = colour
	end
end

--- Render a framebuffer to the screen, swapping its buffers, and handling
--- subpixel conversion
--- @param fb ccFramebuffer
--- @param term cc_term_lib
--- @param dx integer | nil
--- @param dy integer | nil
local function present_framebuffer(fb, term, dx, dy)
	dx = dx or 0
	dy = dy or 0

	local SUBPIXEL_WIDTH = 2
	local SUBPIXEL_HEIGHT = 3

	local fb_front, fb_width = fb.front, fb.width
	fb.front, fb.back = fb.back, fb_front -- swap buffers

	local xBlit = 1 + dx
	local yBlit = 1 + dy

	local string_char = string.char
	local table_unpack = table.unpack
	local table_concat = table.concat
	local term_blit = term.blit
	local term_setCursorPos = term.setCursorPos

	for y = 0, fb.height - 1, SUBPIXEL_HEIGHT do
		local ch_t = {}
		local fg_t = {}
		local bg_t = {}
		local ix = 1

		for x = 1, fb_width, SUBPIXEL_WIDTH do
			local i0 = y * fb_width + x
			local i1 = i0 + fb_width
			local i2 = i1 + fb_width
			local c00, c10 = fb_front[i0], fb_front[i0 + 1]
			local c01, c11 = fb_front[i1], fb_front[i1 + 1]
			local c02, c12 = fb_front[i2], fb_front[i2 + 1]

			local unique_colour_lookup = { [c00] = 0 }
			local unique_colours = 1

			if not unique_colour_lookup[c01] then
				unique_colour_lookup[c01] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c02] then
				unique_colour_lookup[c02] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c10] then
				unique_colour_lookup[c10] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c11] then
				unique_colour_lookup[c11] = unique_colours
				unique_colours = unique_colours + 1
			end
			if not unique_colour_lookup[c12] then
				unique_colour_lookup[c12] = unique_colours
				unique_colours = unique_colours + 1
			end

			if unique_colours == 1 then
				ch_t[ix] = ' '
				fg_t[ix] = '0'
				bg_t[ix] = ch_lookup_char[c00]
			elseif unique_colours > 4 then -- so random that we're gonna just give up lol
				ch_t[ix] = BT_SUBPIXEL_NOISEY
				fg_t[ix] = ch_lookup_char[c01]
				bg_t[ix] = ch_lookup_char[c00]
			else
				local subpixel_code = 0
				local colours = { c00, c10, c01, c11, c02, c12 }

				for i = 6, 1, -1 do
					subpixel_code = subpixel_code * 4
					subpixel_code = subpixel_code + unique_colour_lookup[colours[i]] -- guaranteed to be 0 .. 3 inclusive!
				end

				ch_t[ix] = subpixel_code_ch_lookup[subpixel_code]
				fg_t[ix] = ch_lookup_char[colours[subpixel_code_fg_lookup[subpixel_code]]]
				bg_t[ix] = ch_lookup_char[colours[subpixel_code_bg_lookup[subpixel_code]]]
			end

			ix = ix + 1
		end

		term_setCursorPos(xBlit, yBlit)
		-- term_blit(string_char(table_unpack(ch_t)), string_char(table_unpack(fg_t)), string_char(table_unpack(bg_t)))
		term_blit(table_concat(ch_t), table_concat(fg_t), table_concat(bg_t))
		yBlit = yBlit + 1
	end
end

--------------------------------------------------------------------------------

--- @class ccGeometry: table
--- @field triangles integer

--- @returns ccGeometry
local function create_geometry()
	return { triangles = 0 }
end

--- @param geometry ccGeometry
--- @param p0x number
--- @param p0y number
--- @param p0z number
--- @param p1x number
--- @param p1y number
--- @param p1z number
--- @param p2x number
--- @param p2y number
--- @param p2z number
--- @param colour integer
--- @return nil
local function add_triangle(geometry, p0x, p0y, p0z, p1x, p1y, p1z, p2x, p2y, p2z, colour)
	local DATA_PER_TRIANGLE = 10
	local idx = geometry.triangles * DATA_PER_TRIANGLE

	geometry.triangles = geometry.triangles + 1
	geometry[idx + 1] = p0x
	geometry[idx + 2] = p0y
	geometry[idx + 3] = p0z
	geometry[idx + 4] = p1x
	geometry[idx + 5] = p1y
	geometry[idx + 6] = p1z
	geometry[idx + 7] = p2x
	geometry[idx + 8] = p2y
	geometry[idx + 9] = p2z
	geometry[idx + 10] = colour
end

----------------------------------------------------------------

local function rotate_geometry_z(geometry, theta, cx, cy)
	local DATA_PER_TRIANGLE = 10

	cx = cx or 0
	cy = cy or 0

	local sT = math.sin(theta)
	local cT = math.cos(theta)

	for i = 1, geometry.triangles * DATA_PER_TRIANGLE, DATA_PER_TRIANGLE do
		local x0, y0 = geometry[i], geometry[i + 1]
		local x1, y1 = geometry[i + 3], geometry[i + 4]
		local x2, y2 = geometry[i + 6], geometry[i + 7]
		geometry[i], geometry[i + 1] = x0 * cT - y0 * sT, x0 * sT + y0 * cT
		geometry[i + 3], geometry[i + 4] = x1 * cT - y1 * sT, x1 * sT + y1 * cT
		geometry[i + 6], geometry[i + 7] = x2 * cT - y2 * sT, x2 * sT + y2 * cT
	end
end

--------------------------------------------------------------------------------

--- @class ccCamera
--- @field fov number
--- @field x number
--- @field y number
--- @field z number
--- @field yRotation number
--- @field xRotation number
--- @field zRotation number

--- @param fov number | nil
--- @return ccCamera
local function create_perspective_camera(fov)
	local camera = {}

	camera.fov = fov or math.pi / 3
	camera.x = 0
	camera.y = 0
	camera.z = 0
	camera.yRotation = 0
	camera.xRotation = 0
	camera.zRotation = 0

	return camera
end

--------------------------------------------------------------------------------

--- @private
local function rasterize_flat_triangle(
	fb_front,
	fb_width, fb_height,
	y0, y1,
	lx, lxt,
	rx, rxt,
	xmin, xmax,
	colour)
	-- p*x, p*y are pixel coordinates
	local math_min, math_max, math_floor = math.min, math.max, math.floor
	local y0r = math_floor(y0 + 0.5)
	local y1r = math_floor(y1 + 0.5)
	local y0i = math_max(0, math_min(y0r, fb_height - 1))
	local y1i = math_max(0, math_min(y1r, fb_height - 1))
	local yd = y1 - y0
	local y0Error = (y0i - y0r) / yd
	local y1Error = (y1r - y1i) / yd

	lx = lx + (lxt - lx) * y0Error
	rx = rx + (rxt - rx) * y0Error
	lxt = lxt - (lxt - lx) * y1Error
	rxt = rxt - (rxt - rx) * y1Error

	local ldd = (lxt - lx) / (y1i - y0i)
	local rdd = (rxt - rx) / (y1i - y0i)

	for y = y0i, y1i do
		local yi = y * fb_width + 1
		local lxi = math_max(xmin, math_min(xmax, math_floor(lx + 0.5)))
		local rxi = math_max(xmin, math_min(xmax, math_floor(rx + 0.5)))
		for x = lxi, rxi do
			fb_front[yi + x] = colour
		end
		lx = lx + ldd
		rx = rx + rdd
	end
end

--- @private
local function rasterize_triangle(
	fb_front,
	fb_width, fb_height,
	pxd, pyd,
	pxs, pys,
	p0x, p0y,
	p1x, p1y,
	p2x, p2y,
	colour)
	local math_min, math_max, math_floor = math.min, math.max, math.floor

	-- p*x, p*y are normalised -1 to 1 in a box centred on the centre of the
	-- screen whose height corresponds to the screen height
	if p0y > p1y then
		p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y
	end

	if p1y > p2y then
		p1x, p1y, p2x, p2y = p2x, p2y, p1x, p1y
	end

	if p0y > p1y then
		p0x, p0y, p1x, p1y = p1x, p1y, p0x, p0y
	end

	-- p0, p1, p2 are in height order top -> bottom

	-- convert to screen coordinates
	p0x, p0y = pxd + p0x * pxs, pyd + p0y * pys
	p1x, p1y = pxd + p1x * pxs, pyd + p1y * pys
	p2x, p2y = pxd + p2x * pxs, pyd + p2y * pys
	-- note, p0, p1, p2 are now height order bottom -> top

	if p0y == p2y then
		return -- skip early if we have a perfectly flat triangle
	end

	local midpointX = p0x + (p2x - p0x) * (p1y - p0y) / (p2y - p0y)

	if midpointX == p1x then
		return -- skip early if we have a perfectly flat triangle
	end

	local lx, rx = midpointX, p1x

	if rx < lx then
		lx, rx = rx, lx
	end

	if p0y ~= p1y then
		local xmin = math_max(0, math_floor(math_min(lx, p0x) + 0.5))
		local xmax = math_min(fb_width - 1, math_floor(math_max(rx, p0x) + 0.5))
		rasterize_flat_triangle(fb_front, fb_width, fb_height, p1y, p0y, lx, p0x, rx, p0x, xmin, xmax, colour)
	end

	if p1y ~= p2y then
		local xmin = math_max(0, math_floor(math_min(lx, p2x) + 0.5))
		local xmax = math_min(fb_width - 1, math_floor(math_max(rx, p2x) + 0.5))
		rasterize_flat_triangle(fb_front, fb_width, fb_height, p2y, p1y, p2x, lx, p2x, rx, xmin, xmax, colour)
	end
end

--- @param fb ccFramebuffer
--- @param geometry ccGeometry
--- @param camera ccCamera
local function render_geometry(fb, geometry, camera, aspect_ratio)
	local DATA_PER_TRIANGLE = 10
	local clipping_plane = -0.0001
	local pxd = (fb.width - 1) / 2
	local pyd = (fb.height - 1) / 2
	local pxs = pyd
	local pys = -pyd
	local fb_front, fb_width, fb_height = fb.front, fb.width, fb.height

	aspect_ratio = aspect_ratio or fb.width / fb.height

	local sinX = math.sin(-camera.xRotation)
	local sinY = math.sin(-camera.yRotation)
	local sinZ = math.sin(-camera.zRotation)
	local cosX = math.cos(-camera.xRotation)
	local cosY = math.cos(-camera.yRotation)
	local cosZ = math.cos(-camera.zRotation)
	local scale_y = 1 / math.tan(camera.fov)
	local scale_x = scale_y * aspect_ratio

	local fxx = cosY*cosZ+sinX*sinY*sinZ
	local fxy = cosX*sinZ
	local fxz = -sinY*cosZ + sinX*cosY*sinZ
	local fyx = -cosY*sinZ + sinX*sinY*cosZ
	local fyy = cosX*cosZ
	local fyz = sinY*sinZ + sinX*cosY*cosZ
	local fzx = cosX*sinY
	local fzy = -sinX
	local fzz = cosX*cosY
	local fdx = -camera.x
	local fdy = -camera.y
	local fdz = -camera.z

	for i = 1, geometry.triangles * DATA_PER_TRIANGLE, DATA_PER_TRIANGLE do
		local p0x = geometry[i]
		local p0y = geometry[i + 1]
		local p0z = geometry[i + 2]
		local p1x = geometry[i + 3]
		local p1y = geometry[i + 4]
		local p1z = geometry[i + 5]
		local p2x = geometry[i + 6]
		local p2y = geometry[i + 7]
		local p2z = geometry[i + 8]
		local colour = geometry[i + 9]

		p0x = p0x + fdx
		p0y = p0y + fdy
		p0z = p0z + fdz

		p1x = p1x + fdx
		p1y = p1y + fdy
		p1z = p1z + fdz

		p2x = p2x + fdx
		p2y = p2y + fdy
		p2z = p2z + fdz

		p0x = fxx * p0x + fxy * p0y + fxz * p0z
		p0y = fyx * p0x + fyy * p0y + fyz * p0z
		p0z = fzx * p0x + fzy * p0y + fzz * p0z

		p1x = fxx * p1x + fxy * p1y + fxz * p1z
		p1y = fyx * p1x + fyy * p1y + fyz * p1z
		p1z = fzx * p1x + fzy * p1y + fzz * p1z

		p2x = fxx * p2x + fxy * p2y + fxz * p2z
		p2y = fyx * p2x + fyy * p2y + fyz * p2z
		p2z = fzx * p2x + fzy * p2y + fzz * p2z

		p0x = p0x * scale_x
		p0y = p0y * scale_y
		p1x = p1x * scale_x
		p1y = p1y * scale_y
		p2x = p2x * scale_x
		p2y = p2y * scale_y

		-- TODO: backface culling

		if p0z <= clipping_plane and p1z <= clipping_plane and p2z <= clipping_plane then
			local p0d = -1 / p0z
			local p1d = -1 / p1z
			local p2d = -1 / p2z
			rasterize_triangle(fb_front, fb_width, fb_height, pxd, pyd, pxs, pys, p0x * p0d, p0y * p0d, p1x * p1d, p1y * p1d, p2x * p2d, p2y * p2d, colour)
		end
	end
end

--------------------------------------------------------------------------------

return {
	create_framebuffer = create_framebuffer,
	create_framebuffer_subpixel = create_framebuffer_subpixel,
	clear_framebuffer = clear_framebuffer,
	present_framebuffer = present_framebuffer,
	create_geometry = create_geometry,
	add_triangle = add_triangle,
	rotate_geometry_z = rotate_geometry_z,
	create_perspective_camera = create_perspective_camera,
	rasterize_triangle = rasterize_triangle,
	render_geometry = render_geometry,
}
