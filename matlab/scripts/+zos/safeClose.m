function safeClose(obj)
%SAFECLOSE Close a ZOS-API analysis window or tool if it is still open.
    if nargin < 1 || isempty(obj)
        return
    end
    try
        obj.Close();
    catch
    end
end
