-- HS Gen Code by Siku
-- Turns Hearthstone Cards JSON into a text file for the purpose of machine-learning

require "torch"
require "hsjson"

local pl = require("pl.import_into")() -- Penlight library
local printf = pl.utils.printf

------------------------------------------------------
-- / TORCH COMMAND LINE / --
------------------------------------------------------

local cmd = torch.CmdLine()
cmd:text()
cmd:text('Turn Hearthstone cards JSON into machine-learning text file.')
cmd:text()
--optional lines
cmd:option('-dupe',1,'iterative size of the generated file')
cmd:option('-dump',0,'Dump a filtered version of the input JSON')
cmd:option('-hpwn',0,'should hearthpwn cards be included in output file')
--cmd:option('-extra',0,'add other mechanics as keywords.') -- Not sure about this feature atm
cmd:text()

-- Note: After testing, dupe increase the output file which may be desirable for machine-learning, but 
--                      duplicates will make the RNN learn too well, causing it to generate exact copies of existing cards.

-- parse input params
local opt = cmd:parse(arg)

------------------------------------------------------
-- / TABLES AND CONSTANTS / --
------------------------------------------------------
local DUMP_FILE = "cardlist.txt"
local ERR_FILE = "err.txt"
local RNN_FILE_COPY = "input.txt"
local RNN_FILE_LOCATION = "../torch-rnn/data/input.txt"

-- Card Format: Name @ Class | Race | Type | Rarity | ManaCost | Atk | Health |@ Text &
local HS_CARD_FORMAT = "%s @ %s |%s|%s|%s|%d|%s|%s|@ %s &\n"

--[[
	Effects with text goes at the end.
	Available Letters: JKUY
	$A$ = Adapt
	$B$ = Battlecry
	$C$ = Combo
	$D$ = Deathrattle
	$E$ = Secret
	$F$ = Freeze
	$G$ = Enrage
	$H$ = Choose One
	$I$ = Immune
	$L$ = Lifesteal
	$MX$ = Spell Damage (X = Number)
	$N$ = Inspire
	$OX$ = Overload (X = Number)
	$P$ = Poisonous
	$Q$ = Quest
	$R$ = Charge
	$S$ = Stealth
	$T$ = Taunt
	$V$ = Divine Shield
	$W$ = Windfury
	$X$ = Discover
	$Z$ = Silence
--]]

local keywordReplace = {
	--These are a bit more "hungry" and should be replaced after special cases are handled.
	["<b>Adapt(%.?)</b>"] = "$A$%1",			-- Adapt, Adapt.
	["<b>Battlecr[yi](:?)e?s?</b>"] = "$B$%1",	-- Battlecry, Battlecries, Battlecry:
	["<b>Battlecry:</b>"] = "$B$:",
    ["<b>Battlecry: </b>"] = "$B$: ",
	["<b>Combo:?</b>:?"] = "$C$:",
	["<b>Deathrattles?(:?)</b>"] = "$D$%1", 	-- Deathrattle, Deathrattles, Deathrattle:
	["<b>Secrets?(:?)</b>"] = "$E$%1", 			-- Secret, Secrets, Secret:
	["<b>Fr[eo]e?zen?(%.?)</b>"] = "$F$%1",		-- Freeze, Frozen, Frozen.
	["<b>Enrage:?</b>:?"] = "$G$:",
	["<b>Choose One</b>"] = "$H$",
	["<b>Immune</b>"] = "$I$",
	["<b>Lifesteal</b>"] = "$L$",
	["<b>Spell Damage</b>"] = "$M$",
	["<b>Inspire:</b>"] = "$N$:",
	["<b>Overloade?d?</b>"] = "$O$", 			-- Overload, Overloaded
	["<b>Poisonous</b>"] = "$P$",
	["<b>Charr?r?r?r?ge</b>"] = "$R$", 			-- Charge, Charrrrge
	["<b>Stealth(%.?)e?d?</b>"] = "$S$%1 ", 	-- Stealth, Stealthed, Stealth.
	["<b>Taunt(%.?)</b>"] = " $T$%1",			-- Taunt, Taunt.
    ["<b>Divine Shield(%.?)</b>"] = "$V$%1",	-- Divine Shield, Divine Shield.
	["<b>Windfury</b>"] = "$W$",
	["<b>Mega%-Windfury</b>"] = "$WW$",
	["<b>Discover</b>"] = "$X$",
	["<b>[Ss]ilenced?</b>"] = "$Z$", 			-- Silence, Silenced, silenced
}

local specialReplace = {
	--Initial cleaning
	["<i>.-</i>"] = "",
	["$(%d)"] = "%1*",
	["<b></b>"] = "", -- Why does this even exists?
	["%[x%]"] = "", -- Some cards have a [x] at the beginning. This is to indicate the card has \n added manually in the text.

	--Regular words that were bolded for various reasons
	["<b>Counter</b>"] = "Counter",
	["<b>you</b>"] = "you",
	["<b>Journey to Un'Goro</b>"] = "Journey to Un'Goro",
	["<b>Knights of the Frozen Throne</b>"] = "Knights of the Frozen Throne",
	["<b>Un'Goro</b>"] = "Un'Goro",

	--Keywords with values
	["<b>Choose One %-</b> (.*); (.*)"] = "[$H$ = %1 = %2]",
	["<b>Choose One %- </b>(.*); (.*)"] = "[$H$ = %1 = %2]",
	["<b>Spell Damage %+(%d)</b>"] = "$M%1$",
	["<b>Overload:</b> %((%d)%)"] = "$O%1$ ",
	--["<b>Overload:</b> %((%d)%-(%d)%)"] = "$O%1-%2$ ", -- Hearthpwn made overload mechanic with random value.
	["<b>Quest:</b> (.*) <b>Reward:</b> (.*)"] = "[$Q$ = %1 = %2]",

	--Special cases that combine multiple keywords.
	["<b>Windfury, Charge, Divine Shield, Taunt</b>"] = "$W$ $R$ $V$ $T$", 
	["<b>Windfury, Overload:</b> %((%d)%)"] = "$W$ $O%1$ ",
	["<b>Battlecry and Deathrattle:</b>"] = "$B$ $D$:",     
	["<b>Battlecry: Silence</b>"] = "$B$: $L$",             
	["<b>Charge, Stealth</b>"] = "$R$, $S$",
	["<b>Charge. Deathrattle:</b>"] = "$R$ $D$:",
	["<b>Taunt.? Deathrattle:</b>"] = "$T$ $D$:",            
	["<b>Battlecry: Discover</b>"] = "$B$: $X$",            
	["<b>Choose a Deathrattle %(Secretly%) %-</b> (.*); (.*)"] = "[$HD$ = %1 = %2]",
	
	--Blizzard Hall of Shame replaces:
    ["<b>Quest:</b> (.*).<b> Reward:</b> (.*)"] = "[$Q$ = %1 = %2]",    --, missing a space before Reward, extra space after the <b>.

    --Double Bold
	["<b><b>Freeze</b>s</b>"] = "$F$",                  -- Ice Walker
	["<b><b>Overload</b>ed</b>"] = "$O$",               -- Snowfury Giant
    ["<b><b>Overload</b>:</b> %((%d)%)"] = "$O%1$ ",    -- Jade Claws, Siltfin Spiritwalker
    ["<b><b>Spell Damage</b> %+(%d)</b>"] = "$M%1$",    -- Cult Sorcerer
    ["<b><b>Battlecry:</b> Adapt</b>"] = "$B$: $A$",    -- Pterrodax Hatchling
    ["<b><b>Taunt</b> Battlecry:</b>"] = "$T$ $B$:",    -- Twin-Emperor Vek'lor

    -- Invisible Characters instead of spaces
    ["<b>Spell.*Damage %+(%d)</b>"] = "$M%1$",          -- Ancient Mage
    ["<b>Divine.*Shield</b>"] = "$V$",                  -- Tol'vir Stoneshaper, Howling Commander
    ["<b>Jade.*Golem</b>"] = "{Jade Golem}",            -- Jade Spirit
}

-- This table will fill up from generate_namelist, but lets add a few exceptions.
-- The goal of this set of replaces is to try to improve the RNN behavior by having cards/tribes
--     inside brackets to let it know they arent normal words.
local nameReplace = {
	["<b>Jade Golem</b>"] = "{Jade Golem}", -- .* Needed because Jade Spirit uses non-space character.
	["<b>Death Knight</b>"] = "{Death Knight}",
	["<?b?>?[Ll]egendary<?/?b?>?"] = "{Legendary}",
	["<?b?>?(Spare Parts?)(%.?)<?/?b?>?"] = "{%1}%2",
	["<?b?>?(Hero Power)<?/?b?>?"] = "{%1}",
	["([Mm]ana [Cc]rystals?)"] = "{%1}",
	
	["(Silver Hand Recruits?)"] = "{%1}",
	["(V-07-TR-0N)"] = "{%1}",
	["(Nerubians?)"] = "{%1}",
	["(Oozes?)"] = "{%1}",
	["(Whelps?)"] = "{%1}",
	["(Imps?)"] = "{%1}",
	["(Coins?)"] = "{%1}",

	--Add the tribes too
	["(Elementals?)"] = "{%1}",
	["(Pirates?)"] = "{%1}",
	["(Beasts?)"] = "{%1}",
	["(Murlocs?)"] = "{%1}",
	["(Dragons?)"] = "{%1}",
	["(Totems?)"] = "{%1}",
	["(Demons?)"] = "{%1}",
	["(Mechs?)"] = "{%1}",
}

------------------------------------------------------
-- / FUNCTIONS / --
------------------------------------------------------

function generate_namelist(hsTable)
    for i, card in pairs(hsTable) do
        -- "s?" is added to the format to handle plurals in card texts.
        local nameFormat = string.format("(%ss?)", card.name)
        nameReplace[nameFormat] = "{%1}"
    end
end

-- Name is only ever used for testing purposes
function format_card_effect(text, name)
    if not text then return "" end
    -- Lets get rid of manual newlines.
    local cardText = string.gsub(text, "\n", " ")

    for k,v in pairs(specialReplace) do
        cardText = string.gsub(cardText, k, v)
    end
    for k,v in pairs(keywordReplace) do
        cardText = string.gsub(cardText, k, v)
    end
    for k,v in pairs(nameReplace) do
        cardText = string.gsub(cardText, k, v)
    end

    return pl.stringx.strip(cardText)
end

function format_card(card)
    local title = pl.stringx.title -- Util function to make sure words starts with capital letter, rest lowercase.
    
    local name = card.name

     --Since all tri-class gangs cards are neutral, just use the gang name as the class.
    local class = title(card.cardClass or "NEUTRAL")
    if card.multiClassGroup then class = title(card.multiClassGroup) end

    --Make sure to use Mech instead of Mechanical as that is what is used in card text. 
    local race = title(card.race or "")
    if race == "Mechanical" then race = "Mech" end

    local cardType = title(card.type)
    local rarity = title(card.rarity or "")
    
    local mana = card.cost or 0
    local atk = card.attack or 0
    local hp = (card.health or card.durability) or 0
     --Make sure spells aren't considered 0/0
    if card.type == "Spell" then atk, hp = "", "" end

    -- Card Text can be dynamic, if so, card.collectionText will exist, showing the "static" card text from the Collection Manager. 
    local text
    if card.collectionText then
        text = format_card_effect(card.collectionText, name)
    else
        text = format_card_effect(card.text, name)
    end

    --Last minute filters
    if (text == "$T$" or text == "") and not card.collectible then return end -- Get rid of the plethora of uncollectible taunt/vanilla minions/tokens
    if (text == "" and rarity == "Legendary") then return end -- Get rid of legendaries without effects

    return string.format(HS_CARD_FORMAT, name, class, race, cardType, rarity, mana, atk, hp, text)
end

------------------------------------------------------
-- / CODE ENTRY POINT / --
------------------------------------------------------

do
    local hsTable = json_get_cardlist(opt.dump)
    generate_namelist(hsTable)

    local fileString = ""
    local errString = ""
    local cardCount = 0
    local errCount = 0
    local cardLength = {}
    
    for x, card in pairs(hsTable) do
        local formattedCard = format_card(card)
        if formattedCard then
            cardCount = cardCount + 1
            fileString = fileString..formattedCard
            cardLength[cardCount] = string.len(formattedCard)
            if pl.stringx.lfind(formattedCard, "<") then
                errCount = errCount + 1
                errString = errString..formattedCard
            end
        end
    end
    
    local avgL = 0
    local maxL = 0
    for i = 1, cardCount do
        avgL = avgL + cardLength[i]
        maxL = math.max(maxL, cardLength[i])
    end
    
    --Print useful information
    printf("Total Card Count: %d\n", cardCount)
    printf("Average Card Length: %d\n", avgL / cardCount)
    printf("Longest Card Length: %d\n", maxL)
    if errCount > 0 then
        printf("Total Cards Badly Parsed: %d\n", errCount)
        pl.file.write(ERR_FILE, errString)
    end
    if opt.dupe > 1 then
        local dupeString = ""
        for i = 1, opt.dupe do
            dupeString = dupeString..fileString
        end
        pl.file.write(RNN_FILE_LOCATION, dupeString)
        pl.file.write(RNN_FILE_COPY, dupeString)
    else
        pl.file.write(RNN_FILE_LOCATION, fileString)
        pl.file.write(RNN_FILE_COPY, fileString)
    end

end
