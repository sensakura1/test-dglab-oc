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
        private const string ScriptResourceName = "OCWritingFocusApp.Wpf.ps1";

        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Environment.CurrentDirectory = AppDomain.CurrentDomain.BaseDirectory;

            try
            {
                string script = ReadEmbeddedScript();
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
                    "OC 设定写作督促工具",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private static string ReadEmbeddedScript()
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            using (Stream stream = assembly.GetManifestResourceStream(ScriptResourceName))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("未找到内嵌的桌面程序资源。");
                }

                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    return reader.ReadToEnd();
                }
            }
        }
    }
}
