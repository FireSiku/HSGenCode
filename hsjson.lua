local pl = require("pl.import_into")()
local json = require("json.decode")

--JSON Wrapper
local function hsjson(hsFile)
    return json.decode(pl.file.read(hsFile))
end

------------------------------------------------------
-- / TABLES AND CONSTANTS / --
------------------------------------------------------

local CARDS_FILE_LOCATION = "cards.json"
--local HEARTHPWN_FILE_LOCATION = "HearthpwnS1.json"
local DUMP_FILE = "cardlist.txt"

-- Tables
local legitCardTypes = { "SPELL", "MINION", "WEAPON", "HERO", }
local excludedSets = {"CREDITS", "MISSIONS", "TB", }
local whitelistedTBs = {"TB_KTRAF", "BRMC"} -- KT vs Rafaam, Nefarian vs Rag
local blacklistedIDs = {
    "LOEA04", -- Temple Escape
    "LOEA07", -- Brann Minecart
    "KAR_A10", -- Chess Event
    "HRW",
    "ICC_828t",
    "ICC_047t",
}

function json_verify_card(card)
    --Get rid of hte obvious things
    if not pl.tablex.find(legitCardTypes, card.type) then return end
    if pl.tablex.find(excludedSets, card.set) then
       local shouldExclude = true
       for i = 1, #whitelistedTBs do
           if pl.stringx.lfind(card.id, whitelistedTBs[i]) then
               shouldExclude = false
           end
       end
       if shouldExclude then return end
    end
    for i = 1, #blacklistedIDs do
        if pl.stringx.lfind(card.id, blacklistedIDs[i]) then return end
    end

    --Get rid of Heroic versions of adventure cards or spells shown out of Choose One effects.
    if card.id and string.sub(card.id, -1) == "H" then return end
    if card.id and string.sub(card.id, -1) == "a" then return end
    if card.id and string.sub(card.id, -1) == "b" then return end

    --Do not include adventure cards with no effects, there are just way too many of those.
    if not card.collectible and not card.text then return end

    card.mechanics = nil
	card.dust = nil
	card.artist = nil
	card.texture = nil
	card.howToEarnGolden = nil
	card.howToGetGold = nil
	card.howToEarn = nil
	card.howToGet = nil
	card.playRequirements = nil
	card.targetingArrowText = nil
	card.entourage = nil
    
    return true
end

function json_get_cardlist(dump)
    local cardList = hsjson(CARDS_FILE_LOCATION)
    for k, card in pairs(cardList) do 
        if not json_verify_card(card) then
            cardList[k] = nil
        end
    end

    if dump == 1 then
        pl.pretty.dump(cardList, DUMP_FILE)
    end

    return cardList
end