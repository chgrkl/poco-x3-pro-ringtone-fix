import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.List;

public class ScoRoleFix {
    public static void main(String[] args) throws Exception {
        int strategy = Integer.parseInt(args[0]);
        int role = Integer.parseInt(args[1]);
        String action = args.length > 2 ? args[2] : "set";
        String addr = args.length > 3 ? args[3] : "";
        int nativeType = args.length > 4 ? Integer.parseInt(args[4]) : 0x20;

        Class<?> as = Class.forName("android.media.AudioSystem");
        Class<?> adaCls = Class.forName("android.media.AudioDeviceAttributes");

        if (action.equals("clear")) {
            Method m = as.getMethod("clearDevicesRoleForStrategy", int.class, int.class);
            int r = (Integer) m.invoke(null, strategy, role);
            System.out.println("clearDevicesRoleForStrategy -> " + r + " (0=OK)");
            return;
        }
        Object dev = adaCls.getConstructor(int.class, String.class).newInstance(nativeType, addr);
        List<Object> list = Arrays.asList(dev);
        Method m = as.getMethod("setDevicesRoleForStrategy", int.class, int.class, List.class);
        int r = (Integer) m.invoke(null, strategy, role, list);
        System.out.println("setDevicesRoleForStrategy -> " + r + " (0=OK)");
    }
}