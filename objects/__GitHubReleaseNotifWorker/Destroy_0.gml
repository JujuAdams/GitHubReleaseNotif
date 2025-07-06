// Feather disable all

time_source_destroy(__timeSource);

if (__id != undefined)
{
    //If our HTTP request ID is still valid then we got destroyed before the request could complete.
    //In that situation, recreate this instance and try again.
    
    instance_create_depth(0, 0, 0, __GitHubReleaseNotifWorker, {
        __data: __data,
    });
}