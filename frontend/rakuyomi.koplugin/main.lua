local DocumentRegistry = require("document/documentregistry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext+")
local OfflineAlertDialog = require("OfflineAlertDialog")

local Backend = require("Backend")
local CbzDocument = require("extensions/CbzDocument")
local ErrorDialog = require("ErrorDialog")
local LibraryView = require("LibraryView")
local MangaReader = require("MangaReader")
local Paths = require("Paths")
local Testing = require("testing")

--- A launcher may create this file (inside Rakuyomi's home directory) right
--- before starting KOReader to have the library view opened automatically.
--- The file is consumed on startup, so a regular KOReader launch afterwards
--- is unaffected.
local AUTOSTART_MARKER = "/.autostart"
--- Markers older than this are treated as leftovers (e.g. from a crash
--- before the marker was consumed) and ignored.
local AUTOSTART_MAX_AGE_SECONDS = 120

require("RakuyomiShared")

local disable_logging = G_reader_settings:isTrue("rakuyomi_disable_logging")
if disable_logging then logger:setLevel(logger.levels.err) end

local Rakuyomi = InputContainer:extend({
  name = "rakuyomi"
})

-- We can get initialized from two contexts:
-- - when the `FileManager` is initialized, we're called
-- - when the `ReaderUI` is initialized, we're also called
-- so we should register to the menu accordingly
function Rakuyomi:init()
  if self.ui.name == "ReaderUI" then
    MangaReader:initializeFromReaderUI(self.ui)
  else
    self.ui.menu:registerToMainMenu(self)
    self:consumeAutostartMarker()
  end

  CbzDocument:register(DocumentRegistry)
  Dispatcher:registerAction("start_library_view", {
    category = "none",
    event = "StartLibraryView",
    title = _("Rakuyomi"),
    general = true
  })

  Testing:init()
  Testing:emitEvent('initialized')
end

--- Opens the library view on the next UI tick if a launcher left an autostart
--- marker in Rakuyomi's home directory. The marker is always removed; stale
--- ones are discarded without opening anything.
--- @private
function Rakuyomi:consumeAutostartMarker()
  local marker = Paths.getHomeDirectory() .. AUTOSTART_MARKER
  local attributes = lfs.attributes(marker)
  if attributes == nil then
    return
  end

  os.remove(marker)

  local age = os.time() - (attributes.modification or 0)
  if age > AUTOSTART_MAX_AGE_SECONDS then
    logger.info("rakuyomi: ignoring stale autostart marker", marker, "age", age)
    return
  end

  logger.info("rakuyomi: autostart marker found, opening library view")
  UIManager:nextTick(function()
    self:openLibraryView()
  end)
end

function Rakuyomi:onStartLibraryView()
  if self.ui.name == "ReaderUI" then
    MangaReader:initializeFromReaderUI(self.ui)
  else
    self:openLibraryView()
  end
end

function Rakuyomi:addToMainMenu(menu_items)
  menu_items.rakuyomi = {
    text = _("Rakuyomi"),
    sorting_hint = "search",
    callback = function()
      self:openLibraryView()
    end
  }
end

function Rakuyomi:showErrorDialog()
  ErrorDialog:show(
    _("Oops!") .. _("Rakuyomi encountered an issue while starting up!") .. "\n" ..
    _("Here are some messages that might help identify the problem:") .. "\n\n" ..
    Backend.getLogs(),
    function()
      Backend.cleanup()
      Backend.getBackend()
    end
  )
end

---@class OpenOptions
---@field hideTopClose? boolean - Whether to hide the top close button
---@field focus_manga_id? string
---@field focus_manga_source_id? string
---@param options OpenOptions?
function Rakuyomi:openLibraryView(options)
  Backend.getBackend()
  if not Backend.getInitialized() then
    self:showErrorDialog()

    return
  end

  LibraryView:fetchAndShow(nil, nil, options)
  OfflineAlertDialog:showIfOffline()
end

function Rakuyomi:openFromToolbar()
  self:openLibraryView()
end

return Rakuyomi
