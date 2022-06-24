-- pile
-- virtual base class for Stock, Waste, Foundation, Tableau, Reserve, Cell

local log = require 'log'

local Card = require 'card'
local Util = require 'util'

local Pile = {}
Pile.__index = Pile

local minFanFactor, maxFanFactor = 0.16666, 0.28
local backFanFactor = 0.1

function Pile.new(o)
	-- assert(type(o)=='table')
	-- assert(type(o.x)=='number')
	-- assert(type(o.y)=='number')
	o.slot = {x = o.x, y = o.y}
	o.x, o.y = 0, 0
	o.cards = {}
	o.faceFanFactor = 0.28
	return setmetatable(o, Pile)
end

function Pile:getSavable()
	local cards = {}
	for _, c in ipairs(self.cards) do
		table.insert(cards, c:getSavable())
	end
	return {category=self.category, label=self.label, rune=self.rune, cards=cards}
end

function Pile.isSavable(obj)
	if type(obj) == 'table' then
		-- label, rune and might be nil
		if type(obj.category) == 'string' then
			if type(obj.cards) == 'table' then
				return true
			end
		end
	end
	log.error('not a saved pile')
	return false
end

function Pile:hidden()
	return self.slot.x < 0 or self.slot.y < 0
end

function Pile:setBaizePos(x, y)
	self.x, self.y = x, y
	if self.fanType == 'FAN_DOWN3' then
		local h = _G.BAIZE.cardHeight * self.faceFanFactor
		self.pos1 = {x=x, y=y + h}
		self.pos2 = {x=x, y=y + h * 2}
	elseif self.fanType == 'FAN_LEFT3' then
		local w = _G.BAIZE.cardWidth * self.faceFanFactor
		self.pos1 = {x=x - w, y=y}
		self.pos2 = {x=x - w * 2, y=y}
	elseif self.fanType == 'FAN_RIGHT3' then
		local w = _G.BAIZE.cardWidth * self.faceFanFactor
		self.pos1 = {x=x + w, y=y}
		self.pos2 = {x=x + w * 2, y=y}
	end
end

function Pile:screenPos()
	return self.x + _G.BAIZE.dragOffset.x, self.y + _G.BAIZE.dragOffset.y
end

function Pile:baizeRect()
	return self.x, self.y, _G.BAIZE.cardWidth, _G.BAIZE.cardHeight
end

function Pile:screenRect()
	return self.x + _G.BAIZE.dragOffset.x, self.y + _G.BAIZE.dragOffset.y, _G.BAIZE.cardWidth, _G.BAIZE.cardHeight
end

function Pile:fannedBaizeRect()
	local px, py, pw, ph = self:baizeRect()
	if #self.cards > 1 and self.fanType ~= 'FAN_NONE' then
		local c = self:peek()
		-- if c is being dragged, it will report a large rect
		-- need the rect before it was dragged
		local cx, cy, cw, ch = c:baizeStaticRect()
		if self.fanType == 'FAN_DOWN' or self.fanType == 'FAN_DOWN3' then
			ph = cy - py + ch
		elseif self.fanType == 'FAN_RIGHT' or self.fanType == 'FAN_RIGHT3' then
			pw = cx - px + cw
		elseif self.fanType == 'FAN_LEFT' or self.fanType == 'FAN_LEFT3' then
			px = cx 	-- TODO verify this is correct
			pw = px - cx + cw
		end
	end
	return px, py, pw, ph
end

function Pile:posAfter(c)
	if (c == nil) or (#self.cards == 0) then
		return self.x, self.y
	end
	local x, y
	if c:transitioning() then
		x, y = c.dst.x, c.dst.y
	else
		x, y = c.x, c.y
	end
	if self.fanType == 'FAN_NONE' then
		-- do nothing
	elseif self.fanType == 'FAN_DOWN' then
		if c.prone then
			y = y + (_G.BAIZE.cardHeight * backFanFactor)
		else
			y = y + (_G.BAIZE.cardHeight * self.faceFanFactor)
		end
	elseif self.fanType == 'FAN_RIGHT' then
		if c.prone then
			x = x + (_G.BAIZE.cardWidth * backFanFactor)
		else
			x = x + (_G.BAIZE.cardWidth * self.faceFanFactor)
		end
	elseif self.fanType == 'FAN_LEFT' then
		if c.prone then
			x = x - (_G.BAIZE.cardWidth * backFanFactor)
		else
			x = x - (_G.BAIZE.cardWidth * self.faceFanFactor)
		end
	elseif self.fanType == 'FAN_RIGHT3' or self.fanType == 'FAN_LEFT3' or self.fanType == 'FAN_DOWN3' then
		if #self.cards == 0 then
			-- do nothing (can't ever happen because we know pile is not empty)
		elseif #self.cards == 1 then
			x, y = self.pos1.x, self.pos1.y
		elseif #self.cards == 2 then
			x, y = self.pos2.x, self.pos2.y
		else
			x, y = self.pos2.x, self.pos2.y	-- incoming card at slot 2
			-- top card needs to move from slot 2 to slot 1
			local i = #self.cards
			self.cards[i]:transitionTo(self.pos1.x, self.pos1.y)
			-- mid card needs to move from slot 1 to slot 0
			i = i - 1
			self.cards[i]:transitionTo(self.x, self.y)
			-- remaining cards need to transition to slot 0
			while i > 0 do
				self.cards[i]:transitionTo(self.x, self.y)
				i = i - 1
			end
		end
	end
	return x, y
end

function Pile:refan(fn)
	fn = fn or Card.transitionTo
	if #self.cards == 0 then
		return
	end
	local doFan3 = false
	if self.fanType == 'FAN_NONE' then
		for _, c in ipairs(self.cards) do
			fn(c, self.x, self.y)
		end
	elseif self.fanType == 'FAN_DOWN' or self.fanType == 'FAN_RIGHT' or self.fanType == 'FAN_LEFT' then
		local x, y = self.x, self.y
		local i = 1
		for _, c in ipairs(self.cards) do
			fn(c, x, y)
			x, y = self:posAfter(self.cards[i])
			i = i + 1
		end
	elseif self.fanType == 'FAN_DOWN3' or self.fanType == 'FAN_RIGHT3' or self.fanType == 'FAN_LEFT3' then
		for _, c in ipairs(self.cards) do
			fn(c, self.x, self.y)
		end
		doFan3 = true
	end
	if doFan3 then
		if #self.cards == 0 then
			-- do nothing, already screened out
		elseif #self.cards == 1 then
			-- do nothing
		elseif #self.cards == 2 then
			-- transition the top card
			local c = self.cards[2]
			fn(c, self.pos1.x, self.pos1.y)
		else
			-- transition the top two cards
			local c = self.cards[#self.cards]
			fn(c, self.pos2.x, self.pos2.y)
			c = self.cards[#self.cards - 1]
			fn(c, self.pos1.x, self.pos1.y)
		end
	end
--[[
	-- check to see if any cards have overrun
	if self.fanType == 'FAN_DOWN' then
		local cLast = self:peek()
		local _, cy = cLast:screenPos()
		local _, wh = love.window.getMode()
		if cy + _G.BAIZE.cardHeight > wh - _G.STATUSBARHEIGHT then
			log.info('card', tostring(cLast), 'has overrun')
		end
	end
]]
end

function Pile:baizeBox()
	local box
	if self.box then
		local w, h = love.window.getMode()
		box = {
			x = self.box.x,
			y = self.box.y,
			width = self.box.width,
			height = self.box.height}
		if box.height == -1 then
			box.height = h - _G.STATUSBARHEIGHT - box.y + (_G.BAIZE.cardHeight / 2)
		elseif box.width == -1 then
			box.width = w - box.x
		end
	end
	return box
end

function Pile:screenBox()
	local box = self:baizeBox()
	if box then
		box.x = box.x + _G.BAIZE.dragOffset.x
		box.y = box.y + _G.BAIZE.dragOffset.y
		box.height = box.height -  _G.BAIZE.dragOffset.y
	end
	return box
end

function Pile:calcFanFactor()
	-- result = ((#cards - 1) * (cardheight * factor)) + cardheight
	-- r = (n-1) * (h * f) + h
	-- make factor the subject
	-- f = (r - h) / (h * (n-1))
	-- https://www.mymathtutors.com/algebra-tutors/adding-numerators/online-calculator---rearrange.html

	if (not self.box) or (#self.cards < 4) then
		return false
	end
	local ff
	local box = self:screenBox()
	if self.fanType == 'FAN_DOWN' then
		ff = (box.height - _G.BAIZE.cardHeight) / (_G.BAIZE.cardHeight * (#self.cards - 1))
		ff = Util.clamp(ff, minFanFactor, maxFanFactor)
	elseif self.fanType == 'FAN_RIGHT' or self.fanType == 'FAN_LEFT' then
		ff = (box.width - _G.BAIZE.cardWidth) / (_G.BAIZE.cardWidth * (#self.cards - 1))
		ff = Util.clamp(ff, minFanFactor, maxFanFactor)
	end
	if ff == self.faceFanFactor then
		return false
	end
	self.faceFanFactor = ff
	return true
end

function Pile:peek()
	return self.cards[#self.cards]
end

function Pile:pop()
	local c = table.remove(self.cards)
	if c then
		c.parent = nil
		if self.fanType == 'FAN_RIGHT3' or self.fanType == 'FAN_DOWN3' then
			self:refan(Card.transitionTo)
		end
		c:flipUp()
	end
	return c
end

function Pile:push(c)
	local x, y = self:posAfter(self:peek())
	table.insert(self.cards, c)
	c.parent = self
	c:transitionTo(x, y)
	-- c:setBaizePos(x, y)
end

function Pile:buryCards(ord)
	local tmp = {}
	for _, c in ipairs(self.cards) do
		if c.ord == ord then
			table.insert(tmp, c)
		end
	end
	for _, c in ipairs(self.cards) do
		if c.ord ~= ord then
			table.insert(tmp, c)
		end
	end
	self.cards = {}
	for i = 1, #tmp do
		self:push(tmp[i])
	end
end

function Pile:disinterOneCard(ord, suit)
	-- just move card to top of card stack, ready for popping
	for i, c in ipairs(self.cards) do
		if c.ord == ord and c.suit == suit then
			self.cards[i], self.cards[#self.cards] = self.cards[#self.cards], self.cards[i]
			return c
		end
	end
	return nil
end

function Pile:disinterOneCardByOrd(ord)
	-- just move card to top of card stack, ready for popping
	for i, c in ipairs(self.cards) do
		if c.ord == ord then
			self.cards[i], self.cards[#self.cards] = self.cards[#self.cards], self.cards[i]
			return c
		end
	end
	return nil
end

function Pile:flipUpExposedCard()
	if self.category ~= 'Stock' then
		local c = self:peek()
		if c and c.prone then
			c:flipUp()
		end
	end
end

function Pile:indexOf(card)
	for i, c in ipairs(self.cards) do
		if c == card then
			return i
		end
	end
	return 0
end

function Pile:moveTailError(tail)
	-- check that this type of pile is okay moving this tail from it
--[[
	if tail[1].parent.category ~= 'Stock' then
		for _, c in ipairs(tail) do
			if c.prone then
				return 'Cannot move a face down card'
			end
		end
	end
]]
	-- don't test for MOVE_ANY or MOVE_ONE_PLUS
	-- don't know destination, so we allow MOVE_ONE_PLUS as MOVE_ANY at the moment
	if self.moveType == 'MOVE_NONE' then
		return 'Cannot move a card from that pile'
	elseif self.moveType == 'MOVE_ONE' then
		if #tail > 1 then
			return 'Can only move one card from that pile'
		end
	elseif self.moveType == 'MOVE_ONE_OR_ALL' then
		if not (#tail == 1 or #tail == #self.cards) then
			return 'Only move one card, or the whole pile'
		end
	end
	return nil
end

function Pile:makeTail(c)
	for i=1, #self.cards do
		-- find the first card
		if self.cards[i] == c then
			-- copy rest of cards
			local tail = {}
			for j=i, #self.cards do
				table.insert(tail, self.cards[j])
			end
			return tail
		end
	  end
	return nil
end

function Pile:movableTails()
	-- {dst=<pile>, tail=<tail>}
	-- by default (for discard, foundation), return nothing
	return {}
end

function Pile:updateFromSaved(saved)

	self.cards = {}
	for _, sc in ipairs(saved.cards) do
		-- find sc in _G.BAIZE.deck
		for _, dc in ipairs(_G.BAIZE.deck) do
			if dc.pack == sc.pack and dc.ord == sc.ord and dc.suit == sc.suit then
				if dc.prone ~= sc.prone then
					dc:flip()
				end
				self:push(dc)
				break -- onto next saved card
			end
		end
	end

	self.label = saved.label
	self.faceFanFactor =  0.28
end

-- vtable functions

function Pile.acceptCardError(c)
	log.warn('base acceptCardError should not be called')
	return nil
end

function Pile.acceptTailError(c)
	log.warn('base acceptTailError should not be called')
	return nil
end

function Pile:tailTapped(tail)
	-- assert(tail)
	-- assert(#tail>0)
	local homes = Util.findHomesForTail(tail)
	if homes and #homes > 0 then
		if #homes > 1 then
			table.sort(homes, function(a,b) return a.weight > b.weight end)
		end
		local card = tail[1]
		local src = card.parent
		-- assert(src)
		-- assert(src==self)
		-- assert(homes[1].dst)
		if #tail == 1 then
			Util.moveCard(src, homes[1].dst)
		else
			Util.moveCards(src, src:indexOf(card), homes[1].dst)
		end
	end
end

function Pile:unsortedPairs()
	log.warn('base unsortedPairs should not be called')
end

-- game engine functions

function Pile:update(dt_seconds)
	for _, c in ipairs(self.cards) do
		c:update(dt_seconds)
	end
end

function Pile:drawStaticCards()
	for _, c in ipairs(self.cards) do
		if not (c:transitioning() or c:flipping() or c:dragging()) then
			c:draw()
		end
	end
end

function Pile:drawTransitioningCards()
	for _, c in ipairs(self.cards) do
		if c:transitioning() then
			c:draw()
		end
	end
end

function Pile:drawFlippingCards()
	for _, c in ipairs(self.cards) do
		if c:flipping() then
			c:draw()
		end
	end
end

function Pile:drawDraggingCards()
	for _, c in ipairs(self.cards) do
		if c:dragging() then
			c:draw()
		end
	end
end
--[[
local function drawRotatedRectangle(mode, x, y, width, height, radius, angle)
	-- We cannot rotate the rectangle directly, but we
	-- can move and rotate the coordinate system.
	love.graphics.push()
	love.graphics.translate(x, y)
	love.graphics.rotate(angle)	-- radians
	love.graphics.rectangle(mode, 0, 0, width, height, radius, radius) -- origin in the top left corner
	-- love.graphics.rectangle(mode, -width/2, -height/2, width, height) -- origin in the middle
	love.graphics.pop()
end
]]

--[[
-- This is similar to love.graphics.rectangle, except that the rectangle has
-- rounded corners. r = radius of the corners, n ~ #points used in the polygon.
local function rounded_rectangle(mode, x, y, w, h, r, n)
	n = n or 20  -- Number of points in the polygon.
	if n % 4 > 0 then n = n + 4 - (n % 4) end  -- Include multiples of 90 degrees.
	local pts, c, d, i = {}, {x + w / 2, y + h / 2}, {w / 2 - r, r - h / 2}, 0
	while i < n do
	  local a = i * 2 * math.pi / n
	  local p = {r * math.cos(a), r * math.sin(a)}
	  for j = 1, 2 do
		table.insert(pts, c[j] + d[j] + p[j])
		if p[j] * d[j] <= 0 and (p[1] * d[2] < p[2] * d[1]) then
		  d[j] = d[j] * -1
		  i = i - 1
		end
	  end
	  i = i + 1
	end
	love.graphics.polygon(mode, pts)
end
]]

function Pile:draw()

	if self.nodraw then return end

	local b = _G.BAIZE
	local x, y = self:screenPos()

	if _G.SETTINGS.debug then
		love.graphics.setColor(0, 0, 0, 1)
	else
		love.graphics.setColor(1, 1, 1, 0.1)
	end
	love.graphics.setLineWidth(1)
	love.graphics.rectangle('line', x + 1, y + 1, b.cardWidth - 3, b.cardHeight - 3, b.cardRadius, b.cardRadius, 20)

	if self.label then
		local scale
		if #self.label > 1 then
			scale = 0.8
		else
			scale = 1.0
		end
		love.graphics.setFont(b.labelFont)
		love.graphics.print(self.label,
			x + b.cardWidth / 2,
			y + b.cardHeight / 2,
			0,	-- orientation
			scale,	-- x scale
			scale,	-- y scale
			b.labelFont:getWidth(self.label) / 2,
			b.labelFont:getHeight() / 2)
	end

--[[
	local ssr = self:screenBox()
	if ssr then
		love.graphics.setColor(1,1,1,0.1)
		love.graphics.setLineWidth(1)
		love.graphics.rectangle('line', ssr.x, ssr.y, ssr.width, ssr.height, 10, 10)
	end
]]

--[[
	love.graphics.setColor(1,1,1,1)
	local px, py, pw, ph = self:fannedBaizeRect()	-- should be fannedScreenRect
	love.graphics.rectangle('line', px, py, pw, ph)
]]
end

return Pile
