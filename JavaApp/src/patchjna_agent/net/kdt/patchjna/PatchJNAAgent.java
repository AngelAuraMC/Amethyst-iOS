package net.kdt.patchjna;

import java.io.*;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;

public class PatchJNAAgent implements ClassFileTransformer {
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
    ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
        if (className.equals("com/sun/jna/Platform")) {
            System.out.println("PatchJNAAgent: Replacing JNA Platform class");
            try {
                InputStream inputStream = PatchJNAAgent.class.getClassLoader().getResourceAsStream("com/sun/jna/Platform.class.patch");
                byte[] patched = new byte[inputStream.available()];
                new DataInputStream(inputStream).readFully(patched);
                return patched;
            } catch (Exception e) {
                e.printStackTrace();
            }
        } else if (className.equals("net/caffeinemc/mods/sodium/client/compatibility/checks/PostLaunchChecks")) {
            System.out.println("PatchJNAAgent: Patching Sodium PostLaunchChecks - suppress Pojav check");
            return patchReturnMethod(classfileBuffer, "isUsingPojavLauncher", "()Z", false);
        } else if (className.equals("net/caffeinemc/mods/sodium/client/compatibility/checks/PreLaunchChecks")) {
            System.out.println("PatchJNAAgent: Patching Sodium PreLaunchChecks - fake LWJGL 3.4.1 version");
            return patchReturnMethod(classfileBuffer, "isUsingKnownCompatibleLwjglVersion", "()Z", true);
        }
        return classfileBuffer;
    }

    private static byte[] patchReturnMethod(byte[] classBytes, String methodName, String methodDesc, boolean returnValue) {
        byte[] newCode = returnValue ? new byte[]{0x04, (byte) 0xAC} : new byte[]{0x03, (byte) 0xAC};
        return patchMethod(classBytes, methodName, methodDesc, newCode);
    }

    private static byte[] patchMethod(byte[] classBytes, String methodName, String methodDesc, byte[] newCode) {
        try {
            DataInputStream dis = new DataInputStream(new ByteArrayInputStream(classBytes));
            if (dis.readInt() != 0xCAFEBABE) return classBytes;
            dis.readUnsignedShort(); dis.readUnsignedShort();

            int cpCount = dis.readUnsignedShort();
            String[] cpUtf8 = new String[cpCount];
            int codeUtf8Idx = -1;

            for (int i = 1; i < cpCount; i++) {
                int tag = dis.readUnsignedByte();
                if (tag == 1) {
                    cpUtf8[i] = dis.readUTF();
                    if ("Code".equals(cpUtf8[i])) codeUtf8Idx = i;
                } else if (tag == 5 || tag == 6) { dis.readLong(); i++; }
                else if (tag == 3 || tag == 4 || tag == 16) dis.readInt();
                else if (tag == 7 || tag == 8) dis.readUnsignedShort();
                else if (tag == 9 || tag == 10 || tag == 11 || tag == 12) { dis.readUnsignedShort(); dis.readUnsignedShort(); }
                else if (tag == 15) { dis.readUnsignedByte(); dis.readUnsignedShort(); }
                else if (tag == 17 || tag == 18) { dis.readUnsignedShort(); dis.readUnsignedShort(); }
                else if (tag == 19 || tag == 20) dis.readUnsignedShort();
                else return classBytes;
            }

            dis.readUnsignedShort(); dis.readUnsignedShort(); dis.readUnsignedShort();
            int ic = dis.readUnsignedShort();
            while (ic-- > 0) dis.readUnsignedShort();
            int fc = dis.readUnsignedShort();
            while (fc-- > 0) {
                dis.readUnsignedShort(); dis.readUnsignedShort(); dis.readUnsignedShort();
                int fac = dis.readUnsignedShort();
                while (fac-- > 0) { dis.readUnsignedShort(); dis.skipBytes(dis.readInt()); }
            }

            int mc = dis.readUnsignedShort();

            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            DataOutputStream dos = new DataOutputStream(baos);

            byte[] header = new byte[classBytes.length - dis.available()];
            System.arraycopy(classBytes, 0, header, 0, header.length);
            dos.write(header);

            int codeAttrLen = 12 + newCode.length;

            for (int mi = 0; mi < mc; mi++) {
                int acc = dis.readUnsignedShort();
                int nameIdx = dis.readUnsignedShort();
                int descIdx = dis.readUnsignedShort();
                int ac = dis.readUnsignedShort();

                dos.writeShort(acc);
                dos.writeShort(nameIdx);
                dos.writeShort(descIdx);

                boolean isTarget = methodName.equals(cpUtf8[nameIdx]) && methodDesc.equals(cpUtf8[descIdx]);

                if (isTarget) {
                    dos.writeShort(1);
                    if (codeUtf8Idx > 0) {
                        dos.writeShort(codeUtf8Idx);
                    } else {
                        dos.writeShort(nameIdx);
                    }
                    dos.writeInt(codeAttrLen);
                    dos.writeShort(1);
                    dos.writeShort(0);
                    dos.writeInt(newCode.length);
                    dos.write(newCode);
                    dos.writeShort(0);
                    dos.writeShort(0);
                    for (int aj = 0; aj < ac; aj++) {
                        dis.readUnsignedShort(); dis.skipBytes(dis.readInt());
                    }
                } else {
                    dos.writeShort(ac);
                    for (int aj = 0; aj < ac; aj++) {
                        dos.writeShort(dis.readUnsignedShort());
                        int len = dis.readInt();
                        dos.writeInt(len);
                        byte[] attrData = new byte[len];
                        dis.readFully(attrData);
                        dos.write(attrData);
                    }
                }
            }

            byte[] rest = new byte[dis.available()];
            dis.readFully(rest);
            dos.write(rest);
            dos.flush();
            return baos.toByteArray();
        } catch (Exception e) {
            System.err.println("PatchJNAAgent: Error patching " + methodName + ": " + e);
            e.printStackTrace();
            return classBytes;
        }
    }

    public static void premain(String args, Instrumentation instrumentation) {
        System.out.println("PatchJNAAgent: premain called");
        instrumentation.addTransformer(new PatchJNAAgent());
    }
}
