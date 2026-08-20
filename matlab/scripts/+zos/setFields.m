function setFields(sys, fields)
%SETFIELDS Replace System Explorer fields from requirements.fields.
    if nargin < 2 || zos.countItems(fields) < 1
        fields = [struct('type', 'angle_deg', 'value', 0, 'weight', 1), ...
                  struct('type', 'angle_deg', 'value', 5, 'weight', 1)];
    end
    editor = sys.SystemData.Fields;
    try
        editor.SetFieldType(ZOSAPI.SystemData.FieldType.Angle);
    catch
    end
    while editor.NumberOfFields > 1
        editor.RemoveField(int32(editor.NumberOfFields));
    end
    n = zos.countItems(fields);
    for i = 1:n
        item = zos.getItem(fields, i);
        y = double(zos.localGet(item, 'value', 0));
        w = double(zos.localGet(item, 'weight', 1));
        if i > editor.NumberOfFields
            editor.AddField(0.0, y, w);
        else
            f = editor.GetField(int32(i));
            f.X = 0.0;
            f.Y = y;
            f.Weight = w;
        end
    end
end
