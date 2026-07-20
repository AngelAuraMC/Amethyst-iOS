package git.artdeell.gl4eswrapper;


import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.util.Log;

import java.io.IOException;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        PackageManager packageManager = getPackageManager();
        ApplicationInfo myAppInfo = getApplicationInfo();
        ApplicationInfo targetAppInfo = getAppicationInfo(packageManager);
        if(targetAppInfo == null) {
            finish();
            return;
        }
        String copySrc = myAppInfo.nativeLibraryDir;
        String copyDst = targetAppInfo.nativeLibraryDir;
        if(copySrc == null || copyDst == null || copySrc.isEmpty() || copyDst.isEmpty()) {
            Log.e("GL4ES-W", "Wrong source or destination!");
            Log.e("GL4ES-W", "Source: "+copySrc);
            Log.e("GL4ES-W", "Destination: "+copyDst);
            finish();
            return;
        }
        String copyCommand = "cp " + copySrc + "/* "+copyDst+"/";
        try {
            Runtime.getRuntime().exec("am force-stop "+targetAppInfo.packageName);
            ProcessBuilder processBuilder = new ProcessBuilder("su", "-c", copyCommand);
            Process process = processBuilder.start();
            int errorCode = process.waitFor();
            if(errorCode == 0) {
                startActivity(packageManager.getLaunchIntentForPackage(targetAppInfo.packageName));
            }else {
                Log.e("GL4ES-W", "Copying failed with error code "+errorCode);
            }
        }catch (Exception e) {
            Log.e("GL4ES-W", "Failed to copy files!", e);
        }
        finish();
    }

    public ApplicationInfo getAppicationInfo(PackageManager packageManager) {
        try {
            return packageManager.getApplicationInfo("git.artdeell.mojo.debug", PackageManager.GET_SHARED_LIBRARY_FILES);
        }catch (PackageManager.NameNotFoundException e) {
            return null;
        }
    }
}