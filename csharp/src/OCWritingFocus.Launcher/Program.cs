using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

namespace OCWritingFocus.Launcher
{
    internal static class Program
    {
        private const string DependencyDirectoryName = "OCWritingFocus.dependencies";
        private const string ApplicationFileName = "OCWritingFocus.exe";

        [STAThread]
        private static void Main(string[] args)
        {
            try
            {
                string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
                string dependencyDirectory = Path.Combine(baseDirectory, DependencyDirectoryName);
                string applicationPath = Path.Combine(dependencyDirectory, ApplicationFileName);

                if (!File.Exists(applicationPath))
                {
                    MessageBox.Show(
                        "未找到程序依赖目录。请确保 OCWritingFocus.exe 与 OCWritingFocus.dependencies 文件夹位于同一级目录。",
                        "OC Writing Focus",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return;
                }

                Process.Start(new ProcessStartInfo
                {
                    FileName = applicationPath,
                    WorkingDirectory = dependencyDirectory,
                    Arguments = JoinArguments(args),
                    UseShellExecute = false
                });
            }
            catch (Exception exception)
            {
                MessageBox.Show(
                    "程序启动失败：" + exception.Message,
                    "OC Writing Focus",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
        }

        private static string JoinArguments(string[] args)
        {
            if (args == null || args.Length == 0)
            {
                return string.Empty;
            }

            var builder = new StringBuilder();
            for (int index = 0; index < args.Length; index++)
            {
                if (index > 0)
                {
                    builder.Append(' ');
                }

                builder.Append(QuoteArgument(args[index]));
            }

            return builder.ToString();
        }

        private static string QuoteArgument(string argument)
        {
            if (argument.Length > 0 && argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            {
                return argument;
            }

            var builder = new StringBuilder();
            builder.Append('"');
            int backslashCount = 0;

            foreach (char character in argument)
            {
                if (character == '\\')
                {
                    backslashCount++;
                    continue;
                }

                if (character == '"')
                {
                    builder.Append('\\', backslashCount * 2 + 1);
                    builder.Append('"');
                    backslashCount = 0;
                    continue;
                }

                builder.Append('\\', backslashCount);
                backslashCount = 0;
                builder.Append(character);
            }

            builder.Append('\\', backslashCount * 2);
            builder.Append('"');
            return builder.ToString();
        }
    }
}
