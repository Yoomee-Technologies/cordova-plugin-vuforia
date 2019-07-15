/*===============================================================================
Copyright (c) 2016 PTC Inc. All Rights Reserved.

Copyright (c) 2012-2015 Qualcomm Connected Experiences, Inc. All Rights Reserved.

Vuforia is a trademark of PTC Inc., registered in the United States and other
countries.
===============================================================================*/


package com.mattrayner.vuforia.app;

import android.app.Activity;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.os.AsyncTask;
import android.os.Build;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.OrientationEventListener;
import android.view.WindowManager;
import android.R;

import com.vuforia.CameraCalibration;
import com.vuforia.CameraDevice;
import com.vuforia.Matrix44F;
import com.vuforia.Renderer;
import com.vuforia.State;
import com.vuforia.Tool;
import com.vuforia.Vec2I;
import com.vuforia.VideoBackgroundConfig;
import com.vuforia.VideoMode;
import com.vuforia.Vuforia;
import com.vuforia.Vuforia.UpdateCallbackInterface;

public class ApplicationSession implements UpdateCallbackInterface
{

    private static final String LOGTAG = "Vuforia_Application";

    // Reference to the current activity
    private Activity mActivity;
    private ApplicationControl mSessionControl;

    private String mLicenseKey;

    // Flags
    private boolean mStarted = false;
    private boolean mCameraRunning = false;

    // Display size of the device:
    private int mScreenWidth = 0;
    private int mScreenHeight = 0;

    // The async tasks to initialize the Vuforia SDK:
    private InitVuforiaTask mInitVuforiaTask;
    private LoadTrackerTask mLoadTrackerTask;

    // An object used for synchronizing Vuforia initialization, dataset loading
    // and the Android onDestroy() life cycle event. If the application is
    // destroyed while a data set is still being loaded, then we wait for the
    // loading operation to finish before shutting down Vuforia:
    private Object mShutdownLock = new Object();

    // Vuforia initialization flags:
    private int mVuforiaFlags = 0;

    // Holds the camera configuration to use upon resuming
    private int mCamera = CameraDevice.CAMERA_DIRECTION.CAMERA_DIRECTION_DEFAULT;

    // Stores the projection matrix to use for rendering purposes
    private Matrix44F mProjectionMatrix;

    // Stores viewport to be used for rendering purposes
    private int[] mViewport;

    // Stores orientation
    private boolean mIsPortrait = false;


    public ApplicationSession(ApplicationControl sessionControl, String vuforiaLicense)
    {
        mSessionControl = sessionControl;

        mLicenseKey = vuforiaLicense;
    }


    // Initializes Vuforia and sets up preferences.
    public void initAR(Activity activity, int screenOrientation)
    {
        ApplicationException vuforiaException = null;
        mActivity = activity;

        if ((screenOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR)
            && (Build.VERSION.SDK_INT > Build.VERSION_CODES.FROYO))
            screenOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR;

        // Use an OrientationChangeListener here to capture all orientation changes.  Android
        // will not send an Activity.onConfigurationChanged() callback on a 180 degree rotation,
        // ie: Left Landscape to Right Landscape.  Vuforia needs to react to this change and the
        // ApplicationSession needs to update the Projection Matrix.
        /*
        OrientationEventListener orientationEventListener = new OrientationEventListener(mActivity) {
            @Override
            public void onOrientationChanged(int i) {
                int activityRotation = mActivity.getWindowManager().getDefaultDisplay().getRotation();
                if(mLastRotation != activityRotation)
                {
                    // Signal the ApplicationSession to refresh the projection matrix
                    setProjectionMatrix();
                    mLastRotation = activityRotation;
                }
            }

            int mLastRotation = -1;
        };

        if(orientationEventListener.canDetectOrientation())
            orientationEventListener.enable();

        // Apply screen orientation
        mActivity.setRequestedOrientation(screenOrientation);

        */
        updateActivityOrientation();
        // Query display dimensions:
        storeScreenDimensions();

        // As long as this window is visible to the user, keep the device's
        // screen turned on and bright:
        mActivity.getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        mVuforiaFlags = Vuforia.GL_20;

        // Initialize Vuforia SDK asynchronously to avoid blocking the
        // main (UI) thread.
        //
        // NOTE: This task instance must be created and invoked on the
        // UI thread and it can be executed only once!
        if (mInitVuforiaTask != null)
        {
            String logMessage = "Cannot initialize SDK twice";
            vuforiaException = new ApplicationException(
                ApplicationException.VUFORIA_ALREADY_INITIALIZATED,
                logMessage);
            Log.e(LOGTAG, logMessage);
        }

        if (vuforiaException == null)
        {
            try
            {
                mInitVuforiaTask = new InitVuforiaTask();
                mInitVuforiaTask.execute();
            } catch (Exception e)
            {
                String logMessage = "Initializing Vuforia SDK failed";
                vuforiaException = new ApplicationException(
                    ApplicationException.INITIALIZATION_FAILURE,
                    logMessage);
                Log.e(LOGTAG, logMessage);
            }
        }

        if (vuforiaException != null)
            mSessionControl.onInitARDone(vuforiaException);
    }


    // Starts Vuforia, initialize and starts the camera and start the trackers
    public void startAR(int camera) throws ApplicationException
    {
        String error;
        if(mCameraRunning)
        {
        	error = "Si è verificato un problema, prova a riavviare l'app";
        	Log.e(LOGTAG, error);
            throw new ApplicationException(
                ApplicationException.CAMERA_INITIALIZATION_FAILURE, error);
        }

        mCamera = camera;
        if (!CameraDevice.getInstance().init(camera))
        {
            error = "Si è verificato un problema, prova a riavviare l'app";
            Log.e(LOGTAG, error);
            throw new ApplicationException(
                ApplicationException.CAMERA_INITIALIZATION_FAILURE, error);
        }

        if (!CameraDevice.getInstance().selectVideoMode(
            CameraDevice.MODE.MODE_DEFAULT))
        {
            error = "Si è verificato un problema, prova a riavviare l'app";
            Log.e(LOGTAG, error);
            throw new ApplicationException(
                ApplicationException.CAMERA_INITIALIZATION_FAILURE, error);
        }

        // Configure the rendering of the video background
        configureVideoBackground();

        if (!CameraDevice.getInstance().start())
        {
            error = "Si è verificato un problema, prova a riavviare l'app";
            Log.e(LOGTAG, error);
            throw new ApplicationException(
                ApplicationException.CAMERA_INITIALIZATION_FAILURE, error);
        }

        setProjectionMatrix();

        mSessionControl.doStartTrackers();

        mCameraRunning = true;

        if(!CameraDevice.getInstance().setFocusMode(CameraDevice.FOCUS_MODE.FOCUS_MODE_CONTINUOUSAUTO))
        {
            if(!CameraDevice.getInstance().setFocusMode(CameraDevice.FOCUS_MODE.FOCUS_MODE_TRIGGERAUTO))
                CameraDevice.getInstance().setFocusMode(CameraDevice.FOCUS_MODE.FOCUS_MODE_NORMAL);
        }
    }


    // Stops any ongoing initialization, stops Vuforia
    public void stopAR() throws ApplicationException
    {
        // Cancel potentially running tasks
        if (mInitVuforiaTask != null
            && mInitVuforiaTask.getStatus() != InitVuforiaTask.Status.FINISHED)
        {
            mInitVuforiaTask.cancel(true);
            mInitVuforiaTask = null;
        }

        if (mLoadTrackerTask != null
            && mLoadTrackerTask.getStatus() != LoadTrackerTask.Status.FINISHED)
        {
            mLoadTrackerTask.cancel(true);
            mLoadTrackerTask = null;
        }

        mInitVuforiaTask = null;
        mLoadTrackerTask = null;

        mStarted = false;

        stopCamera();

        // Ensure that all asynchronous operations to initialize Vuforia
        // and loading the tracker datasets do not overlap:
        synchronized (mShutdownLock)
        {

            boolean unloadTrackersResult;
            boolean deinitTrackersResult;

            // Destroy the tracking data set:
            unloadTrackersResult = mSessionControl.doUnloadTrackersData();

            // Deinitialize the trackers:
            deinitTrackersResult = mSessionControl.doDeinitTrackers();

            // Deinitialize Vuforia SDK:
            Vuforia.deinit();
            if (!unloadTrackersResult)
                throw new ApplicationException(
                    ApplicationException.UNLOADING_TRACKERS_FAILURE,
                    "Si è verificato un problema, prova a riavviare l'app");

            if (!deinitTrackersResult)
                throw new ApplicationException(
                    ApplicationException.TRACKERS_DEINITIALIZATION_FAILURE,
                    "Si è verificato un problema, prova a riavviare l'app");

        }
    }


    // Resumes Vuforia, restarts the trackers and the camera
    public void resumeAR() throws ApplicationException
    {
        // Vuforia-specific resume operation
        Vuforia.onResume();

        if (mStarted)
        {
            startAR(mCamera);
        }
    }


    // Pauses Vuforia and stops the camera
    public void pauseAR() throws ApplicationException
    {
        if (mStarted)
        {
            stopCamera();
        }

        Vuforia.onPause();
    }


    // Gets the projection matrix to be used for rendering
    public Matrix44F getProjectionMatrix()
    {
        return mProjectionMatrix;
    }

    // Gets the viewport to be used fo rendering
    public int[] getViewport()
    {
        return mViewport;
    }

    // Callback called every cycle
    @Override
    public void Vuforia_onUpdate(State s)
    {
        mSessionControl.onVuforiaUpdate(s);
    }


    // Manages the configuration changes
    public void onConfigurationChanged()
    {
        updateActivityOrientation();

        storeScreenDimensions();

        if (isARRunning())
        {
            // configure video background
            configureVideoBackground();

            // Update projection matrix:
            setProjectionMatrix();
        }

    }


    // Methods to be called to handle lifecycle
    public void onResume()
    {
        Vuforia.onResume();
    }


    public void onPause()
    {
        Vuforia.onPause();
    }


    public void onSurfaceChanged(int width, int height)
    {
        Vuforia.onSurfaceChanged(width, height);
    }


    public void onSurfaceCreated()
    {
        Vuforia.onSurfaceCreated();
    }

    // An async task to initialize Vuforia asynchronously.
    private class InitVuforiaTask extends AsyncTask<Void, Integer, Boolean>
    {
        // Initialize with invalid value:
        private int mProgressValue = -1;


        protected Boolean doInBackground(Void... params)
        {
            // Prevent the onDestroy() method to overlap with initialization:
            synchronized (mShutdownLock)
            {
                Vuforia.setInitParameters(mActivity, mVuforiaFlags, mLicenseKey);

                do
                {
                    // Vuforia.init() blocks until an initialization step is
                    // complete, then it proceeds to the next step and reports
                    // progress in percents (0 ... 100%).
                    // If Vuforia.init() returns -1, it indicates an error.
                    // Initialization is done when progress has reached 100%.
                    mProgressValue = Vuforia.init();

                    // Publish the progress value:
                    publishProgress(mProgressValue);

                    // We check whether the task has been canceled in the
                    // meantime (by calling AsyncTask.cancel(true)).
                    // and bail out if it has, thus stopping this thread.
                    // This is necessary as the AsyncTask will run to completion
                    // regardless of the status of the component that
                    // started is.
                } while (!isCancelled() && mProgressValue >= 0
                    && mProgressValue < 100);

                return (mProgressValue > 0);
            }
        }


        protected void onProgressUpdate(Integer... values)
        {
            // Do something with the progress value "values[0]", e.g. update
            // splash screen, progress bar, etc.
        }


        protected void onPostExecute(Boolean result)
        {
            // Done initializing Vuforia, proceed to next application
            // initialization status:

            ApplicationException vuforiaException = null;

            if (result)
            {
                Log.d(LOGTAG, "InitVuforiaTask.onPostExecute: Vuforia "
                    + "initialization successful");

                boolean initTrackersResult;
                initTrackersResult = mSessionControl.doInitTrackers();

                if (initTrackersResult)
                {
                    try
                    {
                        mLoadTrackerTask = new LoadTrackerTask();
                        mLoadTrackerTask.execute();
                    } catch (Exception e)
                    {
                        String logMessage = "Si è verificato un problema, prova a riavviare l'app";
                        vuforiaException = new ApplicationException(
                            ApplicationException.LOADING_TRACKERS_FAILURE,
                            logMessage);
                        Log.e(LOGTAG, logMessage);
                        mSessionControl.onInitARDone(vuforiaException);
                    }

                } else
                {
                    vuforiaException = new ApplicationException(
                        ApplicationException.TRACKERS_INITIALIZATION_FAILURE,
                        "Si è verificato un problema, prova a riavviare l'app");
                    mSessionControl.onInitARDone(vuforiaException);
                }
            } else
            {
                String logMessage;

                // NOTE: Check if initialization failed because the device is
                // not supported. At this point the user should be informed
                // with a message.
                logMessage = getInitializationErrorString(mProgressValue);

                // Log error:
                Log.e(LOGTAG, "InitVuforiaTask.onPostExecute: " + logMessage
                    + " Exiting.");

                // Send Vuforia Exception to the application and call initDone
                // to stop initialization process
                vuforiaException = new ApplicationException(
                    ApplicationException.INITIALIZATION_FAILURE,
                    logMessage);
                mSessionControl.onInitARDone(vuforiaException);
            }
        }
    }

    // An async task to load the tracker data asynchronously.
    private class LoadTrackerTask extends AsyncTask<Void, Integer, Boolean>
    {
        protected Boolean doInBackground(Void... params)
        {
            // Prevent the onDestroy() method to overlap:
            synchronized (mShutdownLock)
            {
                // Load the tracker data set:
                return mSessionControl.doLoadTrackersData();
            }
        }


        protected void onPostExecute(Boolean result)
        {

            ApplicationException vuforiaException = null;

            Log.d(LOGTAG, "LoadTrackerTask.onPostExecute: execution "
                + (result ? "successful" : "failed"));

            if (!result)
            {
                String logMessage = "Si è verificato un problema, prova a riavviare l'app";
                // Error loading dataset
                Log.e(LOGTAG, logMessage);
                vuforiaException = new ApplicationException(
                    ApplicationException.LOADING_TRACKERS_FAILURE,
                    logMessage);
            } else
            {
                // Hint to the virtual machine that it would be a good time to
                // run the garbage collector:
                //
                // NOTE: This is only a hint. There is no guarantee that the
                // garbage collector will actually be run.
                System.gc();

                Vuforia.registerCallback(ApplicationSession.this);

                mStarted = true;
            }

            // Done loading the tracker, update application status, send the
            // exception to check errors
            mSessionControl.onInitARDone(vuforiaException);
        }
    }


    // Returns the error message for each error code
    private String getInitializationErrorString(int code)
    {
        if (code == Vuforia.INIT_DEVICE_NOT_SUPPORTED)
            return "App non compatibile con il tuo dispositivo.";
        if (code == Vuforia.INIT_NO_CAMERA_ACCESS)
            return "Vai su Impostazioni e consenti all'app Guarda! di accedere alla fotocamera.";
        if (code == Vuforia.INIT_LICENSE_ERROR_MISSING_KEY)
            return "Codice errore 123971. Prova a riavviare l'app o contatta l'assistenza Zanichelli.";
        if (code == Vuforia.INIT_LICENSE_ERROR_INVALID_KEY)
            return "Codice errore 387581. Prova a riavviare l'app o contatta l'assistenza Zanichelli.";
        if (code == Vuforia.INIT_LICENSE_ERROR_NO_NETWORK_TRANSIENT)
            return "Potrebbe esserci un problema di rete. Prova a riavviare l'app.";
        if (code == Vuforia.INIT_LICENSE_ERROR_NO_NETWORK_PERMANENT)
            return "Connetti il tuo dispositivo a Internet per utilizzare Guarda!.";
        if (code == Vuforia.INIT_LICENSE_ERROR_CANCELED_KEY)
            return "Codice errore 948671. Prova a riavviare l'app o contatta l'assistenza Zanichelli.";
        if (code == Vuforia.INIT_LICENSE_ERROR_PRODUCT_TYPE_MISMATCH)
            return "Codice errore 573931. Prova a riavviare l'app o contatta l'assistenza Zanichelli.";
        else
        {
            return "Codice errore 754812. Prova a riavviare l'app o contatta l'assistenza Zanichelli.";
        }
    }


    // Stores screen dimensions
    private void storeScreenDimensions()
    {
        // Query display dimensions:
        DisplayMetrics metrics = new DisplayMetrics();
        mActivity.getWindowManager().getDefaultDisplay().getMetrics(metrics);
        mScreenWidth = metrics.widthPixels;
        mScreenHeight = metrics.heightPixels;
    }


    // Stores the orientation depending on the current resources configuration
    private void updateActivityOrientation()
    {
        Configuration config = mActivity.getResources().getConfiguration();

        switch (config.orientation)
        {
            case Configuration.ORIENTATION_PORTRAIT:
                mIsPortrait = true;
                break;
            case Configuration.ORIENTATION_LANDSCAPE:
                mIsPortrait = false;
                break;
            case Configuration.ORIENTATION_UNDEFINED:
            default:
                break;
        }

        Log.i(LOGTAG, "Activity is in "
            + (mIsPortrait ? "PORTRAIT" : "LANDSCAPE"));
    }


    // Method for setting / updating the projection matrix for AR content
    // rendering
    public void setProjectionMatrix()
    {
        CameraCalibration camCal = CameraDevice.getInstance()
            .getCameraCalibration();
        mProjectionMatrix = Tool.getProjectionGL(camCal, 10.0f, 5000.0f);
    }


    public void stopCamera()
    {
        if(mCameraRunning)
        {
            mSessionControl.doStopTrackers();
            CameraDevice.getInstance().stop();
            CameraDevice.getInstance().deinit();
            mCameraRunning = false;
        }
    }


    // Configures the video mode and sets offsets for the camera's image
    private void configureVideoBackground()
    {
        CameraDevice cameraDevice = CameraDevice.getInstance();
        VideoMode vm = cameraDevice.getVideoMode(CameraDevice.MODE.MODE_DEFAULT);

        VideoBackgroundConfig config = new VideoBackgroundConfig();
        config.setEnabled(true);
        config.setPosition(new Vec2I(0, 0));

        int xSize = 0, ySize = 0;
        if (mIsPortrait)
        {
            xSize = (int) (vm.getHeight() * (mScreenHeight / (float) vm
                .getWidth()));
            ySize = mScreenHeight;

            if (xSize < mScreenWidth)
            {
                xSize = mScreenWidth;
                ySize = (int) (mScreenWidth * (vm.getWidth() / (float) vm
                    .getHeight()));
            }
        } else
        {
            xSize = mScreenWidth;
            ySize = (int) (vm.getHeight() * (mScreenWidth / (float) vm
                .getWidth()));

            if (ySize < mScreenHeight)
            {
                xSize = (int) (mScreenHeight * (vm.getWidth() / (float) vm
                    .getHeight()));
                ySize = mScreenHeight;
            }
        }

        config.setSize(new Vec2I(xSize, ySize));

        // The Vuforia VideoBackgroundConfig takes the position relative to the
        // centre of the screen, where as the OpenGL glViewport call takes the
        // position relative to the lower left corner
        mViewport = new int[4];
        mViewport[0] = ((mScreenWidth - xSize) / 2) + config.getPosition().getData()[0];
        mViewport[1] = ((mScreenHeight - ySize) / 2) + config.getPosition().getData()[1];
        mViewport[2] = xSize;
        mViewport[3] = ySize;

        Log.i(LOGTAG, "Configure Video Background : Video (" + vm.getWidth()
            + " , " + vm.getHeight() + "), Screen (" + mScreenWidth + " , "
            + mScreenHeight + "), mSize (" + xSize + " , " + ySize + ")");

        Renderer.getInstance().setVideoBackgroundConfig(config);

    }

    // Returns true if Vuforia is initialized, the trackers started and the
    // tracker data loaded
    private boolean isARRunning()
    {
        return mStarted;
    }

}
