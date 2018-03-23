local pl = require"pl.import_into"()
local socket = require "socket"
local ltn12 = require "ltn12"
local https = require("ssl.https")

local Network = {}
local API_URL = "https://api.hearthstonejson.com/v1/"

function Network.get_scheme(url)
    if not string.find(url, "//") then url = "//"..url end
    local parsed = socket.url.parse(url)
    return parsed.scheme
end

-- Downloads a file using https protocol
function Network.get_file(url, name)
    local file = name and io.open(name, "wb")
    local scheme = Network.get_scheme(url)
    if scheme == "https" then
        local save = ltn12.sink.file(file or io.stdout)
        local request_table = { url = url, sink = save }
        local res, code, header, status = https.request(request_table)
        if code ~= 200 then io.stderr:write(status or code, "\n") end
    else
        print("Invalid Scheme" .. scheme)
    end
end

function Network.check_versions()
    local file = io.open("networkTest.txt")
    local vers = {}
    --├── <a href="/v1/18336/">18336</a><br>
    for line in file:lines() do
        local ver = string.match(line, ".*<a href=./v1/%d+/.>(%d+)</a><br>")
        if ver then
            table.insert(vers,ver)
            local card_file = string.format("data/cards-%s.json", ver)
            if not pl.path.isfile(card_file) then
                local card_url = string.format("%s%s/enUS/cards.json", API_URL, ver)
                Network.get_file(card_url, card_file)
                if not pl.path.isfile(card_file) then
                    io.stderr:write(string.format("Error getting cards-%s.json, it could not be downloaded..\n", ver))
                end
            end
        end
    end
end

function Network.get_latest_version()
    local files = pl.dir.getfiles("data")
    local ver = string.match(files[#files], "data.cards.(%d+).json")
    return files[#files], ver
end

--TODO: Add --update to check for new version and --force to re-download them.
--Network.get_file(API_URL, "networkTest.txt")
--Network.check_versions()
--Network.get_latest_version()

return Network