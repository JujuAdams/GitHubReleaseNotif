// Feather disable all

//Send the HTTP request off to GitHub
__id = http_get($"https://github.com/{__data.__username}/{__data.__libraryName}/releases/latest/");

//Time source to check if we get disabled during operation for some reason
__timeSource = time_source_create(time_source_global, 1, time_source_units_frames, function()
{
    if (not instance_exists(self))
    {
        instance_activate_object(self);
        
        if (instance_exists(self))
        {
            //Create a new worker using our own values.
            instance_create_depth(0, 0, 0, __GitHubReleaseNotifWorker, {
                __data: __data,
            });
            
            __id = undefined;
            instance_destroy();
        }
    }
},
[], -1);

time_source_start(__timeSource);