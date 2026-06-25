local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local _ = require("gettext")

local KindleFetch = WidgetContainer:extend{
    name = "kindlefetch",
    is_doc_only = false,
}

local bridge = "/mnt/us/extensions/kindlefetch/bin/koreader_bridge.sh"
local search_output = "/tmp/kindlefetch-koreader-search.txt"
local download_output = "/tmp/kindlefetch-koreader-download.txt"

local function shell_quote(value)
    value = tostring(value or "")
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local file = io.open(path, "r")
    if not file then return "" end
    local data = file:read("*a") or ""
    file:close()
    data = data:gsub("\027%[[0-9;?]*[A-Za-z]", "")
    return data
end

local function run_command(command, output_path)
    local full_command = command .. " > " .. shell_quote(output_path) .. " 2>&1"
    return os.execute(full_command)
end

function KindleFetch:init()
    self.ui.menu:registerToMainMenu(self)
end

function KindleFetch:addToMainMenu(menu_items)
    menu_items.kindlefetch = {
        text = _("KindleFetch"),
        sorting_hint = "more_tools",
        callback = function()
            self:showSearchDialog()
        end,
    }
end

function KindleFetch:showSearchDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("KindleFetch search"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local query = dialog:getInputText()
                        UIManager:close(dialog)
                        if query and query ~= "" then
                            self:runSearch(query)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleFetch:runSearch(query)
    UIManager:show(InfoMessage:new{ text = _("Searching...") })
    run_command(shell_quote(bridge) .. " search " .. shell_quote(query), search_output)
    local output = read_file(search_output)
    if output == "" then
        output = _("No output from KindleFetch.")
    end
    self:showResults(output)
end

function KindleFetch:showResults(output)
    local viewer
    viewer = TextViewer:new{
        title = _("KindleFetch results"),
        title_multilines = true,
        text = output,
        text_type = "code",
        buttons_table = {
            {
                {
                    text = _("New search"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showSearchDialog()
                    end,
                },
                {
                    text = _("Download"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showDownloadDialog()
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function KindleFetch:showDownloadDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Download result number"),
        input = "",
        input_type = "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Download"),
                    is_enter_default = true,
                    callback = function()
                        local choice = dialog:getInputText()
                        UIManager:close(dialog)
                        if choice and choice ~= "" then
                            self:runDownload(choice)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleFetch:runDownload(choice)
    UIManager:show(InfoMessage:new{ text = _("Downloading...") })
    run_command(shell_quote(bridge) .. " download " .. shell_quote(choice), download_output)
    local output = read_file(download_output)
    if output == "" then
        output = _("No output from KindleFetch.")
    end
    UIManager:show(InfoMessage:new{
        text = output,
        timeout = 0,
    })
end

return KindleFetch
