using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace OCWritingFocus
{
    internal static class Program
    {
        private const string AppDirectoryName = "app";
        private const string ScriptFileName = "OCWritingFocusApp.Wpf.ps1";
        private const string QrCoderFileName = "QRCoder.dll";

        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Environment.CurrentDirectory = AppDomain.CurrentDomain.BaseDirectory;
            AppDomain.CurrentDomain.AssemblyResolve += ResolveExternalAssembly;

            try
            {
                string script = ReadExternalScript();
                using (Runspace runspace = RunspaceFactory.CreateRunspace())
                {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    runspace.Open();

                    using (PowerShell powershell = PowerShell.Create())
                    {
                        powershell.Runspace = runspace;
                        powershell.AddScript(script);
                        powershell.Invoke();

                        if (powershell.HadErrors)
                        {
                            StringBuilder message = new StringBuilder();
                            foreach (ErrorRecord error in powershell.Streams.Error)
                            {
                                if (message.Length > 0)
                                {
                                    message.AppendLine();
                                }
                                message.Append(error.ToString());
                            }
                            throw new InvalidOperationException(message.ToString());
                        }
                    }
                }
            }
            catch (Exception exception)
            {
                string errorLogPath = Path.Combine(
                    AppDomain.CurrentDomain.BaseDirectory,
                    "OCWritingFocus.startup-error.log");
                try
                {
                    File.WriteAllText(errorLogPath, exception.ToString(), Encoding.UTF8);
                }
                catch
                {
                    // The message box remains available when the install directory is read-only.
                }

                MessageBox.Show(
                    "程序启动失败：\r\n\r\n" + exception.Message +
                    "\r\n\r\n错误日志：" + errorLogPath,
                    "OC 写作专注工具",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private static string GetAppFilePath(string fileName)
        {
            return Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory,
                AppDirectoryName,
                fileName);
        }

        private static string ReadExternalScript()
        {
            string scriptPath = GetAppFilePath(ScriptFileName);
            if (!File.Exists(scriptPath))
            {
                throw new FileNotFoundException(
                    "未找到桌面程序脚本，请确保 app 文件夹与 EXE 一起分发。",
                    scriptPath);
            }

            using (StreamReader reader = new StreamReader(scriptPath, Encoding.UTF8, true))
            {
                return reader.ReadToEnd();
            }
        }

        private static Assembly ResolveExternalAssembly(object sender, ResolveEventArgs args)
        {
            AssemblyName requested = new AssemblyName(args.Name);
            if (!string.Equals(requested.Name, "QRCoder", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            string assemblyPath = GetAppFilePath(QrCoderFileName);
            return File.Exists(assemblyPath) ? Assembly.LoadFrom(assemblyPath) : null;
        }
    }
}
