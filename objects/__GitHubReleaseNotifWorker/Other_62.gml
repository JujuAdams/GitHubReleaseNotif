// Feather disable all

//Function to extract the tag name and datetime stamp from the returned HTML document.
var _funcExtract = function(_string, _subString)
{
    var _pq = ds_priority_create();
    var _pos = 0;
    
    while(true)
    {
        _pos = string_pos_ext(_subString, _string, _pos+1);
        if (_pos <= 0) break;
        
        var _substring = string_copy(_string, _pos + string_length(_subString), 50);
        var _i = 1;
        repeat(50)
        {
            var _char = string_char_at(_substring, _i);
            if ((_char == "'") || (_char == "\"") || (_char == "&") || (_char == "*"))
            {
                break;
            }
            
            ++_i;
        }
        
        var _tag = string_copy(_substring, 1, _i-1);
        if (_tag != "")
        {
            var _priority = ds_priority_find_priority(_pq, _tag);
            ds_priority_add(_pq, _tag, (_priority ?? 0) + 1);
        }
    }
    
    var _result = ds_priority_find_max(_pq);
    ds_priority_destroy(_pq);
    
    return _result;
}

if (async_load[? "id"] == __id)
{
    if (async_load[? "status"] > 0)
    {
        //HTTP request pending. This is common in this use case because the HTML document we receive is
        //pretty big.
    }
    else if (async_load[? "status"] < 0)
    {
        //HTTP request failed for some reason.
        __data.__complete = true;
        
        //Unset the ID here to indicate we've completed handling the request.
        __id = undefined;
        instance_destroy();
    }
    else // == 0
    {
        //HTTP request successful (or at least we got a response we can make sense of).
        
        if (async_load[? "http_status"] != 200)
        {
            //HTTP request failed - usually indicates a server problem.
            __data.__complete = true;
        }
        else
        {
            var _string = async_load[? "result"];
            var _latestTag = _funcExtract(_string, $"{__data.__libraryName}/releases/tag/");
            var _timestamp = _funcExtract(_string, "datetime=\"");
            
            if (not is_string(_latestTag))
            {
                //We couldn't find valid tag information. Is the HTML document corrupted?
                __data.__complete = true;
            }
            else
            {
                __GitHubReleaseNotifSystem().__lastCheck = date_current_datetime();
                
                //Pass on found values to the repo's data container.
                with(__data)
                {
                    __complete  = true;
                    __checkDate = date_current_datetime();
                    
                    __gitHubVersion = _latestTag;
                    __gitHubDate    = __GitHubReleaseNotifConvertTimestamp(_timestamp);
                }
            }
        }
        
        //Unset the ID here to indicate we've completed handling the request.
        __id = undefined;
        instance_destroy();
    }
}