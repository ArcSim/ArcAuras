-- QOL\AD_GearListOrder.lua: every dungeon's and raid's bosses in run order, by the instance's map ID.
-- Read by NS.GearList for the dungeon the player is in; made from the client's DungeonEncounter table by
-- tools\gen_gearlist_order.js.
local ADDON, NS = ...

NS.GearListOrder = {
    [13] = { "Rahuz" }, -- Test Dungeon
    [33] = { "Rethilgore", "Razorclaw the Butcher", "Baron Silverlaine", "Commander Springvale", "Odo the Blindwatcher", "Fenrus the Devourer", "Wolf Master Nandos", "Archmage Arugal" }, -- Shadowfang Keep
    [34] = { "Targorr the Dread", "Kam Deepfury", "Hamhock", "Dextren Ward", "Bazil Thredd" }, -- Stormwind Stockade
    [36] = { "Rhahk'Zor", "Sneed", "Miner Johnson", "Gilnid", "Captain Greenskin", "Mr. Smite", "Cookie", "Edwin VanCleef" }, -- Deadmines
    [43] = { "Lady Anacondra", "Lord Cobrahn", "Kresh", "Lord Pythas", "Skum", "Lord Serpentis", "Verdan the Everliving", "Mutanus the Devourer" }, -- Wailing Caverns
    [47] = { "Roogug", "Aggem Thorncurse", "Death Speaker Jargba", "Overlord Ramtusk", "Agathelos the Raging", "Charlga Razorflank" }, -- Razorfen Kraul
    [48] = { "Baron Aquanis", "Ghamoo-ra", "Lady Sarevess", "Geilhast", "Gelihast", "Lorgus Jett", "Old Serra'kis", "Twilight Lord Kelris", "Aku'mai" }, -- Blackfathom Deeps
    [70] = { "Revelosh", "The Lost Dwarves", "Ironaya", "Obsidian Sentinel", "Ancient Stone Keeper", "Galgann Firehammer", "Grimlok", "Archaedas" }, -- Uldaman
    [90] = { "Grubbis", "Viscous Fallout", "Electrocutioner 6000", "Crowd Pummeler 9-60", "Mekgineer Thermaplugg", "Mechanical Menagerie" }, -- Gnomeregan
    [109] = { "Avatar of Hakkar", "Jammal'an the Prophet", "Dreamscythe", "Festering Rotslime", "Weaver", "Atal'ai Defenders", "Dreamscythe and Weaver", "Morphaz", "Jammal'an and Ogom", "Hazzas", "Morphaz and Hazzas", "Shade of Eranikus", "Atal'alarion" }, -- Sunken Temple
    [129] = { "Tuten'kash", "Plaguemaw the Rotting", "Mordresh Fire Eye", "Ragglesnout", "Glutton", "Amnennar the Coldbringer" }, -- Razorfen Downs
    [189] = { "Interrogator Vishas", "Bloodmage Thalnos", "Houndmaster Loksey", "Arcanist Doan", "Herod", "High Inquisitor Fairbanks", "High Inquisitor Whitemane" }, -- Scarlet Monastery
    [209] = { "Hydromancer Velratha", "Gahz'rilla", "Antu'sul", "Theka the Martyr", "Witch Doctor Zum'rah", "Nekrum Gutchewer", "Shadowpriest Sezz'ziz", "Chief Ukorz Sandscalp" }, -- Zul'Farrak
    [229] = { "Highlord Omokk", "Shadow Hunter Vosh'gajin", "War Master Voone", "Mother Smolderweb", "Urok Doomhowl", "Quartermaster Zigris", "Halycon", "Gizrul the Slavener", "Overlord Wyrmthalak", "Pyroguard Emberseer", "Warchief Rend Blackhand", "The Beast", "General Drakkisath", "Lord Valthalak" }, -- Blackrock Spire
    [230] = { "High Interrogator Gerstahn", "Lord Roccor", "Houndmaster Grebmar", "Ring of Law", "Pyromancer Loregrain", "Lord Incendius", "Warder Stilgiss", "Fineous Darkvire", "Bael'Gar", "General Angerforge", "Golem Lord Argelmach", "Hurley Blackbreath", "Phalanx", "Ribbly Screwspigot", "Plugger Spazzring", "The Vault", "Ambassador Flamelash", "The Seven", "Magmus", "Princess Moira Bronzebeard", "Emperor Dagran Thaurissan" }, -- Blackrock Depths
    [249] = { "Onyxia" }, -- Onyxia's Lair
    [289] = { "Kirtonos", "Jandice Barov", "Rattlegore", "Marduk Blackpool", "Vectus", "Kormok", "Ras Frostwhisperer", "Instructor Malicia", "Doctor Theolen Krastinov", "Lorekeeper Polkelt", "The Ravenian", "Lord Alexei Barov", "Lady Illucia Barov", "Darkmaster Gandling" }, -- Scholomance
    [309] = { "High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "Bloodlord Mandokir", "Edge of Madness", "High Priest Thekal", "Gahz'ranka", "High Priestess Arlokk", "Jin'do the Hexxer", "Hakkar" }, -- Zul'Gurub
    [329] = { "Hearthsinger Forresten", "Timmy the Cruel", "Malor the Zealous", "Cannon Master Willey", "Archivist Galford", "Balnazzar", "The Unforgiven", "Baroness Anastari", "Nerub'enkan", "Maleki the Pallid", "Magistrate Barthilas", "Ramstein the Gorger", "Baron Rivendare", "Black Guard Swordsmith", "Crimson Hammersmith", "Ezra Grimm", "Postmaster Malown", "Skul", "Stonespine" }, -- Stratholme
    [349] = { "Noxxion", "Razorlash", "Tinkerer Gizlock", "Lord Vyletongue", "Celebras the Cursed", "Landslide", "Rotgrip", "Princess Theradras" }, -- Maraudon
    [389] = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" }, -- Ragefire Chasm
    [409] = { "Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Sulfuron Harbinger", "Golemagg the Incinerator", "Majordomo Executus", "Ragnaros", "The Molten Core" }, -- Molten Core
    [429] = { "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Pusillin", "Alzzin the Wildshaper", "Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar", "Prince Tortheldrin", "Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik", "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok", "Lord Hel'nurath", "Tsu'zee" }, -- Dire Maul
    [469] = { "Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw", "Ebonroc", "Flamegor", "Chromaggus", "Nefarian" }, -- Blackwing Lair
    [509] = { "Kurinnaxx", "General Rajaxx", "Moam", "Buru the Gorger", "Ayamiss the Hunter", "Ossirian the Unscarred" }, -- Ruins of Ahn'Qiraj
    [531] = { "The Prophet Skeram", "Silithid Royalty", "Battleguard Sartura", "Fankriss the Unyielding", "Viscidus", "Princess Huhuran", "Twin Emperors", "Ouro", "C'thun" }, -- Ahn'Qiraj Temple
    [533] = { "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean", "Loatheb", "Instructor Razuvious", "Gothik the Harvester", "The Four Horsemen", "Patchwerk", "Grobbulus", "Gluth", "Thaddius", "Sapphiron", "Kel'Thuzad" }, -- Naxxramas
    [2720] = { "Testwerk" }, -- The Searing Basin
    [2784] = { "Grimroot", "Destructor's Wraith", "Zilbagob", "Pyranis", "Diathorus the Seeker", "Hellscream's Phantom", "Azgaloth" }, -- Demon Fall Canyon
    [2789] = { "Lord Kazzak" }, -- The Tainted Scar
    [2791] = { "Azuregos" }, -- Storm Cliffs
    [2804] = { "Prince Thunderaan" }, -- The Crystal Vale
    [2832] = { "Emeriss", "Lethon", "Taerar", "Ysondre" }, -- Nightmare Grove
    [2856] = { "Balnazzar", "Beatrix", "Beastmaster", "Solistrasza", "Mason", "Reborn Council", "Lillian Voss", "Caldoran" }, -- Scarlet Enclave
    [2875] = { "Harbinger of Sin", "Creeping Malison", "Three Little Wolves", "Dark Rider", "Kharon", "Unk'omon", "Hans and Greta", "The Ugly Goblin", "Kaigy Maryla", "Sairuh Maryla", "Barian Maryla" }, -- Karazhan Crypts
    [2921] = { "Spirit of Mograine" }, -- Naxxramas
    [2959] = { "Arcane Anomaly", "Fel Ancient", "Mana Devourer", "Mana Elemental", "Unstable Sentinel", "Lyn the Ignored", "Atrexis the Grave Knight", "Mana Wraith", "Shade of the Archmage" }, -- City of Dalaran
    [2970] = { "Zul'Alai", "Var'Taka", "Captain Dreadrise", "Deathless Guardians", "Primeval Elemental", "Min'loth the Serpent" }, -- The Drowned City
    [2974] = { "Withermaw", "Impaan the Imprisoner", "Elder Shaman Bloodmane", "Bonesnout the Unbroken", "Varrox Bleakhoof", "Blackmaw Behemoth", "Unbound Spirit" }, -- Blackmaw Hold
    [2994] = { "Overseer Wrex", "Tidemistress Ca'zass", "Katerina the Cleaner", "The Questioner", "Blazeroar" }, -- Alcaz Prison
    [2998] = { "Saltspine", "Shadetooth", "Highland Horror", "Relic Guardian" }, -- Excavation Site: Wetlands
    [2999] = { "Witherfang", "The Abandoned", "The Butcher", "Lordaeron Captain", "Viktor the Vile", "Bjork", "Rath'mael" }, -- Ruins of Lordaeron
    [3001] = { "Titanosaur", "Ravasaur Hunters", "Thunderhoof", "Venomridge", "Direhorn Matriarch", "Cinder", "King Op", "Snowtalon", "Bolt", "Vitrix", "Nanaya" }, -- The Shaper's Terrace
    [3039] = { "Slavecrusher Grox", "Twilight Commander Zarmok", "Handler Ashka", "Nar'gurk", "Overseer Mugg" }, -- Krol'dok Stronghold
    [3065] = { "Faldrim Anvilmar", "Infurnus", "Plunder", "Durgen Dirgehammer" }, -- The Hall of Thanes
}
