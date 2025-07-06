// Feather disable all

/// Sends off a request to GitHub to collect the latest release for a repo. If a version newer than
/// the local version is found, a message will be shown in the debug log and a visual notification,
/// constructed in GameMaker's native debug overlay, may be shown. No notifications will ever be
/// visible to players.
/// 
/// N.B. This function must be called on boot i.e. in the root of a script.
/// 
/// This tool will only work when running the game from the IDE and when running the game on a
/// desktop platform (Windows, MacOS, Linux). There are also rate limits built into this tool.
/// Firstly, requests to GitHub will be made once per day per library and data collected from
/// GitHub will be cached. Secondly, the visual notification in the debug overlay will only be
/// shown once every 3 months per project (regardless of the number of libraries using this tool).
/// If the library user would like to manually check for updates, there is a dedicated button in
/// the debug overlay for this.
/// 
/// This function processes data obtained from the generic GitHub latest release URL for your repo.
/// As a result, this function will only pick up the release marked as "latest" on GitHub. This
/// means releases marked as "pre-release" will not get picked up.
/// 
/// The `username` and `libraryName` parameters must be provided as strings. These should match the
/// associated names on GitHub; for example, I would choose `"JujuAdams"` and `"scribble"` for one
/// of my libraries hosted at `https://github.com/JujuAdams/scribble`. If in doubt, use the values
/// from the URL for your repo.
/// 
/// The `versionString` parameter should be formatted as `"major.minor.patch"` in accordance with
/// semantic versioning (see https://semver.org/). Any characters after the patch number will be
/// ignored by this tool.
/// 
/// N.B. Each GitHub release tag that you choose must also follow semantic versioning. The version
///      string programmed into your game must match the version string used for the release tag on
///      GitHub.
/// 
/// The `dateString` parameter should be formatted as per ISO 8601 (`"yyyy-mm-dd"`). This tool does
/// not take time (hours/minutes/seconds) into account so you need only specify the year/month/day.
/// You should take care to ensure that the date string matches the date that you publish your
/// release on GitHub.
/// 
/// `showNotification` should normally be set to `true`. However, if you'd like to prevent your
/// library from showing notifications in-game then set this parameter to `false`. Regardless of
/// the value of this parameter, messages will still be shown in the debug log.
/// 
/// Finally, the optional parameter `manualRequestOnly` is available to prevent automatic requests
/// being sent to GitHub. Instead, the user will have to manually check for updates using the
/// button in the debug overlay.
/// 
/// @param username
/// @param libraryName
/// @param versionString
/// @param dateString
/// @param showNotification
/// @param [manualRequestOnly=false]

function GitHubReleaseNotif(_username, _libraryName, _versionString, _dateString, _showNotification, _manualRequestOnly = false)
{
    static _system       = __GitHubReleaseNotifSystem();
    static _libraryArray = _system.__libraryArray;
    
    if ((GM_build_type == "run") && ((os_type == os_windows) || (os_type == os_macosx) || (os_type == os_linux)))
    {
        var _key = $"{_username}/{_libraryName}";
        
        var _gitHubVersion = undefined;
        var _gitHubDate    = undefined;
        var _complete      = _manualRequestOnly;
        var _checkDate     = 0;
        
        var _cachedData = _system.__cachedData[$ _key];
        if (is_struct(_cachedData))
        {
            _gitHubVersion = _cachedData[$ "version"];
            _gitHubDate    = _cachedData[$ "releaseDate"];
            
            var _checkDate = _cachedData[$ "checkDate"] ?? 0;
            if (date_day_span(date_current_datetime(), _checkDate) < 1)
            {
                _complete = true;
            }
        }
        
        var _data = {
            __username:         _username,
            __libraryName:      _libraryName,
            __localVersion:     _versionString,
            __localDate:        __GitHubReleaseNotifConvertTimestamp(_dateString),
            __showNotification: _showNotification,
            
            __key: _key,
            
            __gitHubVersion: _gitHubVersion,
            __gitHubDate:    _gitHubDate,
            
            __complete:   _complete,
            __checkDate:  _checkDate,
            __newRelease: false,
        };
        
        array_push(_libraryArray, _data);
    }
}

function __GitHubReleaseNotifSystem()
{
    static _system = undefined;
    if (_system != undefined) return _system;
    
    _system = {};
    with(_system)
    {
        __libraryArray = [];
        __filename = game_save_id + "/github-releases.json";
        __forcedUpdate = false;
        
        if ((GM_build_type == "run") && ((os_type == os_windows) || (os_type == os_macosx) || (os_type == os_linux)))
        {
            var _json = {};
            
            if (file_exists(__filename))
            {
                try
                {
                    var _buffer = buffer_load(__filename);
                    var _jsonString = buffer_read(_buffer, buffer_text);
                    buffer_delete(_buffer);
                    
                    var _json = json_parse(_jsonString);
                }
                catch(_error)
                {
                    show_debug_message($"Failed to load \"{__filename}\"");
                }
            }
            
            __lastNotification = _json[$ "notifyDate"] ??  0;
            __lastCheck        = _json[$ "checkDate" ] ??  0;
            __cachedData       = _json[$ "cache"     ] ?? {};
            
            __funcCreateWorkers = function()
            {
                var _i = 0;
                repeat(array_length(__libraryArray))
                {
                    var _library = __libraryArray[_i];
                    if (__forcedUpdate || (not _library.__complete))
                    {
                        instance_create_depth(0, 0, 0, __GitHubReleaseNotifWorker, { __data: _library });
                    }
                    
                    ++_i;
                }
            }
            
            //Delay creation for a frame to ensure we're in a room. This works around situations where
            //this function is called on boot.
            call_later(10, time_source_units_frames, __funcCreateWorkers);
            
            __timeSource = time_source_create(time_source_global, 1, time_source_units_seconds, function()
            {
                static _system = __GitHubReleaseNotifSystem();
                static _libraryArray = _system.__libraryArray;
                
                //Function to compare two version numbers.
                var _funcCompareVersion = function(_localVersion, _otherVersion)
                {
                    _localVersion = _funcStrip(_localVersion);
                    _otherVersion = _funcStrip(_otherVersion);
                    
                    static _funcStrip = function(_string)
                    {
                        var _i = 1;
                        repeat(string_length(_string))
                        {
                            var _ord = ord(string_char_at(_string, _i));
                            
                            if not (((_ord >= 48) && (_ord <= 57)) || (_ord == 46))
                            {
                                break;
                            }
                            
                            ++_i;
                        }
                        
                        return string_copy(_string, 1, _i-1);
                    }
                    
                    static _funcSplit = function(_versionString)
                    {
                        static _funcSafeReal = function(_string)
                        {
                            if (_string == "") return 0;
                            
                            try
                            {
                                var _value = real(_string);
                            }
                            catch(_error)
                            {
                                var _value = 0;
                            }
                            
                            return _value;
                        }
                        
                        var _array = string_split(_versionString, ".", false, 3);
                        array_resize(_array, 3);
                        
                        var _i = 0;
                        repeat(array_length(_array))
                        {
                            _array[@ _i] = _funcSafeReal(_array[_i]);
                            ++_i;
                        }
                        
                        return _array;
                    }
                    
                    var _localArray = _funcSplit(_localVersion);
                    var _otherArray = _funcSplit(_otherVersion);
                    
                    if (_localArray[0] > _otherArray[0]) return  1;
                    if (_localArray[0] < _otherArray[0]) return -1;
                    
                    if (_localArray[1] > _otherArray[1]) return  1;
                    if (_localArray[1] < _otherArray[1]) return -1;
                    
                    if (_localArray[2] > _otherArray[2]) return  1;
                    if (_localArray[2] < _otherArray[2]) return -1;
                    
                    return 0;
                }
                
                var _showDebugOverlay = false;
                var _i = 0;
                repeat(array_length(_libraryArray))
                {
                    if (_libraryArray[_i].__complete)
                    {
                        with(_libraryArray[_i])
                        {
                            //Figure out if the incoming version is newer than what we have.
                            __newRelease = (_funcCompareVersion(__localVersion, __gitHubVersion) < 0);
                            if (__newRelease == undefined)
                            {
                                //In situations where the version cannot safely be determined (usually a problem with either the
                                //local version string or tag formatting) then we fall back on the date stamp.
                                __newRelease = (date_compare_datetime(__localDate, __gitHubDate) < 0);
                            }
                            
                            if (__showNotification && __newRelease)
                            {
                                _showDebugOverlay = true;
                            }
                        }
                    }
                    else
                    {
                        return;
                    }
                    
                    ++_i;
                }
                
                if (date_month_span(date_current_datetime(), __lastNotification) < 3)
                {
                    _showDebugOverlay = false;
                }
                
                time_source_stop(__timeSource);
                var _oldOpen = is_debug_overlay_open();
                
                dbg_view("GitHub Release", __forcedUpdate || _showDebugOverlay, 0.5*(display_get_gui_width() - 550), 0.5*(display_get_gui_height() - 550), 550, 550);
                dbg_section("General", true);
                
                dbg_text("");
                
                dbg_button("CLOSE DEBUG OVERLAY", function()
                {
                    show_debug_overlay(false);
                });
                
                dbg_text("");
                
                dbg_button("Check releases now", function()
                {
                    time_source_start(__timeSource);
                    __forcedUpdate = true;
                    __funcCreateWorkers();
                });
                
                if (__lastCheck <= 0)
                {
                    dbg_text($"Last checked for updates: (unknown)");
                }
                else
                {
                    dbg_text($"Last checked for updates: {date_datetime_string(__lastCheck)}");
                }
                
                dbg_text("");
                
                array_sort(_libraryArray, function(_a, _b)
                {
                    return (_a.__key < _b.__key)? -1 : 1;
                });
                
                var _i = 0;
                repeat(array_length(_libraryArray))
                {
                    var _library = _libraryArray[_i];
                    with(_library)
                    {
                        //Show a message in the debug log if a new version is available.
                        if (__newRelease)
                        {
                            show_debug_message($"New version available for {__username}/{__libraryName}: Version \"{__gitHubVersion}\" was released on {date_date_string(__gitHubDate)}.");
                            show_debug_message($"Please visit https://github.com/{__username}/{__libraryName}/releases/latest/ for more information.");
                            
                            var _sectionName = $"{__key}   v{__localVersion}   NEW VERSION";
                        }
                        else
                        {
                            var _sectionName = $"{__key}   v{__localVersion}";
                        }
                        
                        dbg_section(_sectionName, __newRelease);
                        dbg_text($"Your version: {__localVersion} ({date_date_string(__localDate)})");
                        
                        if (__gitHubVersion == undefined)
                        {
                            dbg_text("Failed to retrieve latest release (was the repo moved?)");
                        }
                        else
                        {
                            if (__newRelease)
                            {
                                dbg_text("");
                                dbg_text("New version available!");
                                
                                dbg_text($"Latest version: {__gitHubVersion}");
                                
                                if (__gitHubDate != undefined)
                                {
                                    dbg_text($"Release date: {date_date_string(__gitHubDate)}");
                                }
                                
                                dbg_button("Open in browser", function()
                                {
                                    url_open($"https://github.com/{__username}/{__libraryName}/releases/latest/");
                                });
                            }
                            else
                            {
                                if (__gitHubDate == undefined)
                                {
                                    dbg_text($"Latest version: {__gitHubVersion} (unknown release date)");
                                }
                                else
                                {
                                    dbg_text($"Latest version: {__gitHubVersion} ({date_date_string(__gitHubDate)})");
                                }
                                
                                dbg_text("");
                            }
                        }
                    }
                    
                    ++_i;
                }
                
                if (_showDebugOverlay)
                {
                    __lastNotification = date_current_datetime();
                    show_debug_overlay(true);
                }
                else if (not _oldOpen)
                {
                    show_debug_overlay(false);
                }
                
                var _cacheData = {};
                var _json = {
                    notifyDate: __lastNotification,
                    checkDate:  __lastCheck,
                    cache:      _cacheData,
                };
                
                var _i = 0;
                repeat(array_length(__libraryArray))
                {
                    var _library = __libraryArray[_i];
                    _cacheData[$ _library.__key] = {
                        version:     _library.__gitHubVersion,
                        releaseDate: _library.__gitHubDate,
                        checkDate:   _library.__checkDate,
                    };
                    
                    ++_i;
                }
                
                var _buffer = buffer_create(1024, buffer_grow, 1);
                buffer_write(_buffer, buffer_text, json_stringify(_json));
                buffer_save_ext(_buffer, __filename, 0, buffer_tell(_buffer));
                buffer_delete(_buffer);
                
                __forcedUpdate = false;
            },
            [], -1);
            
            time_source_start(__timeSource);
        }
        else
        {
            __timeSource = undefined;
        }
    }
    
    return _system;
}

//Function to convert an ISO 8601 datestamp into a native GameMaker datetime number.
function __GitHubReleaseNotifConvertTimestamp(_timestamp)
{
    if (not is_string(_timestamp)) return 0;
    
    var _rootSplit = string_split(_timestamp, "T", true, 1);
    var _dateSplit = string_split(_rootSplit[0], "-", false, 2);
    
    if (array_length(_dateSplit) != 3)
    {
        return 0;
    }
    
    static _funcSafeReal = function(_string)
    {
        if (_string == "") return undefined;
        
        try
        {
            var _value = real(_string);
        }
        catch(_error)
        {
            return undefined;
        }
        
        return _value;
    }
    
    array_map_ext(_dateSplit, _funcSafeReal);
    if (array_get_index(_dateSplit, undefined) >= 0) return 0;
    
    return date_create_datetime(_dateSplit[0], _dateSplit[1], _dateSplit[2], 0, 0, 0);
}