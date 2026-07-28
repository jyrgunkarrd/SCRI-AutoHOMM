local imageLoader = {}

local webp
local IMAGE_SETTINGS = {
    mipmaps = true,
}

local function getExtension(path)
    return path:match("%.([^%.]+)$")
end

local function isWebP(path)
    local extension = getExtension(path)
    return extension and extension:lower() == "webp"
end

local function getWebP()
    if not webp then
        webp = require("src.render.love-webp")
    end

    return webp
end

local function applyImageFiltering(image)
    image:setFilter("linear", "linear", 1)
    image:setMipmapFilter("linear", 0)

    return image
end

function imageLoader.newImage(path)
    if not isWebP(path) then
        return applyImageFiltering(love.graphics.newImage(path, IMAGE_SETTINGS))
    end

    local data = love.filesystem.read(path)
    if not data then
        error("Unable to read WebP image: " .. path)
    end

    local imageData = getWebP().loadImage(data)
    if not imageData then
        error("Unable to decode WebP image: " .. path)
    end

    return applyImageFiltering(love.graphics.newImage(imageData, IMAGE_SETTINGS))
end

function imageLoader.newWebPAnimation(path)
    local data = love.filesystem.read(path)
    if not data then
        error("Unable to read WebP animation: " .. path)
    end

    local animation = getWebP().loadAnimation(data)
    if not animation then
        error("Unable to decode WebP animation: " .. path)
    end

    applyImageFiltering(animation.texture)

    return animation
end

function imageLoader.applyImageFiltering(image)
    return applyImageFiltering(image)
end

return imageLoader
