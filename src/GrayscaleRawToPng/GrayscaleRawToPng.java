package GrayscaleRawToPng;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;

import java.io.FileOutputStream;
import java.io.InputStream;

import org.opencv.imgcodecs.Imgcodecs;
import org.opencv.core.Core;
import org.opencv.core.CvType;
import org.opencv.core.Mat;
import org.opencv.highgui.HighGui;


public class GrayscaleRawToPng {
	public static void loadOpenCV() {
	    String os = System.getProperty("os.name").toLowerCase();
	    String arch = System.getProperty("os.arch").toLowerCase();

	    String resourcePath;
	    String fileName;

	    if (os.contains("win")) {
	        if (arch.contains("64")) {
	            resourcePath = "/native/windows/x64/";
	        } else {
	            throw new RuntimeException("目前不支援 32-bit Windows");
	        }

	        fileName = "opencv_java500.dll";

	    } else if (os.contains("mac")) {

	        if (arch.equals("aarch64") || arch.equals("arm64")) {
	            resourcePath = "/native/macos/arm64/";
	        } else {
	            resourcePath = "/native/macos/x64/";
	        }

	        fileName = "libopencv_java500.dylib";

	    } else if (os.contains("linux")) {

	        if (arch.equals("amd64") || arch.equals("x86_64")) {
	            resourcePath = "/native/linux/x64/";
	        } else if (arch.equals("aarch64") || arch.equals("arm64")) {
	            resourcePath = "/native/linux/arm64/";
	        } else {
	            throw new RuntimeException(
	                    "目前不支援此 Linux 架構：" + arch
	            );
	        }

	        fileName = "libopencv_java500.so";

	    } else {
	        throw new RuntimeException(
	                "不支援的作業系統：" + os
	        );
	    }

	    String fullResourcePath =
	            resourcePath + fileName;

	    try (InputStream in =
	                 GrayscaleRawToPng.class
	                         .getResourceAsStream(fullResourcePath)) {

	        if (in == null) {
	            throw new RuntimeException(
	                    "JAR 內找不到 OpenCV："
	                    + fullResourcePath
	            );
	        }

	        String suffix =
	                fileName.substring(
	                        fileName.lastIndexOf('.')
	                );

	        File tempLib =
	                File.createTempFile(
	                        "opencv_",
	                        suffix
	                );

	        tempLib.deleteOnExit();

	        try (FileOutputStream out =
	                     new FileOutputStream(tempLib)) {

	            byte[] buffer =
	                    new byte[8192];

	            int read;

	            while ((read = in.read(buffer)) != -1) {
	                out.write(
	                        buffer,
	                        0,
	                        read
	                );
	            }
	        }

	        System.load(
	                tempLib.getAbsolutePath()
	        );

	        System.out.println(
	                "OpenCV 載入成功"
	        );

	        System.out.println(
	                "OS: " + os
	        );

	        System.out.println(
	                "Architecture: " + arch
	        );

	        System.out.println(
	                "OpenCV Version: "
	                + Core.VERSION
	        );

	    } catch (Exception | UnsatisfiedLinkError e) {

	        System.err.println(
	                "OpenCV 載入失敗"
	        );

	        e.printStackTrace();

	        throw new RuntimeException(
	                "無法載入 OpenCV native library",
	                e
	        );
	    }
	}
	public static String removeEnd(String str, String remove) {
		if (str != null && remove != null && str.endsWith(remove)) {
			return str.substring(0, str.length() - remove.length());
		}
		return str;
	}
    public static ArrayList<String> readAllFiles(
            String filePath
    ) {

        ArrayList<String> allFiles =
                new ArrayList<>();


        File file;

        if (
                filePath == null ||
                filePath.isEmpty()
        ) {

            file = new File(".");

        } else {

            file = new File(filePath);
        }


        // 資料夾
        if (file.isDirectory()) {

            File[] files =
                    file.listFiles();


            if (files == null) {
                return allFiles;
            }


            for (File child : files) {

                allFiles.addAll(
                        readAllFiles(
                                child.getPath()
                        )
                );
            }
        }

        // 檔案
        else {

            String fileName =
                    file.getName()
                            .toLowerCase();


            if (
                    fileName.endsWith(".raw") ||
                    fileName.equals("lena")
            ) {

                allFiles.add(
                        file.getPath()
                );
            }
        }


        return allFiles;
    }

	public static void main(String[] args) throws Exception {
		loadOpenCV();
		ArrayList<String> list = readAllFiles("");
		

		System.out.println(list);
		for (String path : list) {

            Path p = Path.of(path);
			byte[] img = Files.readAllBytes(p);

			Mat newImg = new Mat(512, 512, CvType.CV_8UC1);
			newImg.put(0, 0, img);

			String imgName = removeEnd(p.getFileName().toString(), ".raw") + ".png";
			Imgcodecs.imwrite(imgName, newImg);

			
			HighGui.imshow(imgName, newImg);
          
		}
		 HighGui.waitKey(0);

	}

}
