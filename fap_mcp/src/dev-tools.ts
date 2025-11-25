/**
 * Development Tools for FAP MCP
 *
 * Provides hot reload, file operations, code analysis, and test execution
 * to enable autonomous AI testing and development workflows.
 */

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import http from "node:http";

// VM Service client for hot reload
export class VmServiceClient {
    private vmServiceUri: string | null = null;
    private isolateId: string | null = null;

    setUri(uri: string) {
        this.vmServiceUri = uri;
        this.isolateId = null; // Reset isolate when URI changes
    }

    getUri(): string | null {
        return this.vmServiceUri;
    }

    /**
     * Get the main isolate ID
     */
    private async getIsolateId(): Promise<string> {
        if (this.isolateId) return this.isolateId;
        if (!this.vmServiceUri) throw new Error('VM Service URI not set');

        const vmInfo = await this.callVmService('getVM', {});
        const isolates = vmInfo.result?.isolates;
        if (!isolates || isolates.length === 0) {
            throw new Error('No isolates found');
        }
        const id = isolates[0].id;
        if (!id) {
            throw new Error('Isolate has no ID');
        }
        this.isolateId = id;
        return id;
    }

    /**
     * Call VM Service via HTTP
     */
    private callVmService(method: string, params: Record<string, any>): Promise<any> {
        return new Promise((resolve, reject) => {
            if (!this.vmServiceUri) {
                reject(new Error('VM Service URI not set. Call set_vm_service_uri first.'));
                return;
            }

            try {
                const url = new URL(this.vmServiceUri);
                const requestData = JSON.stringify({
                    jsonrpc: '2.0',
                    id: '1',
                    method,
                    params
                });

                const options: http.RequestOptions = {
                    hostname: url.hostname,
                    port: url.port || 80,
                    path: url.pathname,
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Content-Length': Buffer.byteLength(requestData)
                    },
                    timeout: 30000
                };

                const req = http.request(options, (res) => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        try {
                            resolve(JSON.parse(data));
                        } catch {
                            resolve({ result: data });
                        }
                    });
                });

                req.on('error', reject);
                req.on('timeout', () => reject(new Error('VM Service request timeout')));
                req.write(requestData);
                req.end();
            } catch (e) {
                reject(e);
            }
        });
    }

    /**
     * Trigger hot reload
     */
    async hotReload(): Promise<{ success: boolean; message: string }> {
        if (!this.vmServiceUri) {
            return { success: false, message: 'VM Service URI not set. Call set_vm_service_uri first.' };
        }

        try {
            const isolateId = await this.getIsolateId();
            const result = await this.callVmService('reloadSources', { isolateId });

            if (result.error) {
                return { success: false, message: `Hot reload failed: ${result.error.message}` };
            }

            return { success: true, message: 'Hot reload successful' };
        } catch (e: any) {
            return { success: false, message: `Hot reload error: ${e.message}` };
        }
    }

    /**
     * Trigger hot restart
     */
    async hotRestart(): Promise<{ success: boolean; message: string }> {
        if (!this.vmServiceUri) {
            return { success: false, message: 'VM Service URI not set. Call set_vm_service_uri first.' };
        }

        try {
            // Hot restart requires calling the Flutter tool's extension
            const result = await this.callVmService('ext.flutter.reassemble', {});

            if (result.error) {
                return { success: false, message: `Hot restart failed: ${result.error.message}` };
            }

            return { success: true, message: 'Hot restart successful' };
        } catch (e: any) {
            return { success: false, message: `Hot restart error: ${e.message}` };
        }
    }

    /**
     * Get VM info
     */
    async getVmInfo(): Promise<any> {
        if (!this.vmServiceUri) {
            return { error: 'VM Service URI not set' };
        }

        try {
            return await this.callVmService('getVM', {});
        } catch (e: any) {
            return { error: e.message };
        }
    }
}

// File operations
export class FileOperations {
    private projectRoot: string;

    constructor(projectRoot?: string) {
        this.projectRoot = projectRoot || process.cwd();
    }

    setProjectRoot(root: string) {
        this.projectRoot = root;
    }

    getProjectRoot(): string {
        return this.projectRoot;
    }

    /**
     * Resolve a path relative to project root
     */
    private resolvePath(filePath: string): string {
        if (path.isAbsolute(filePath)) {
            return filePath;
        }
        return path.join(this.projectRoot, filePath);
    }

    /**
     * Read a file
     */
    readFile(filePath: string): { success: boolean; content?: string; error?: string } {
        try {
            const resolved = this.resolvePath(filePath);

            if (!fs.existsSync(resolved)) {
                return { success: false, error: `File not found: ${filePath}` };
            }

            const content = fs.readFileSync(resolved, 'utf-8');
            return { success: true, content };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }

    /**
     * Write a file
     */
    writeFile(filePath: string, content: string): { success: boolean; error?: string } {
        try {
            const resolved = this.resolvePath(filePath);

            // Ensure directory exists
            const dir = path.dirname(resolved);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }

            fs.writeFileSync(resolved, content, 'utf-8');
            return { success: true };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }

    /**
     * Search for code patterns using grep
     */
    searchCode(pattern: string, filePattern: string = '*.dart'): { success: boolean; matches?: Array<{ file: string; line: number; content: string }>; error?: string } {
        try {
            // Use spawnSync with argument array (safe from injection)
            const result = spawnSync('grep', ['-rn', '--include', filePattern, pattern, this.projectRoot], {
                encoding: 'utf-8',
                timeout: 30000,
                maxBuffer: 10 * 1024 * 1024
            });

            if (result.error) {
                return { success: false, error: result.error.message };
            }

            const matches: Array<{ file: string; line: number; content: string }> = [];
            const lines = (result.stdout || '').split('\n').filter(Boolean);

            for (const line of lines) {
                const match = line.match(/^(.+?):(\d+):(.*)$/);
                if (match) {
                    matches.push({
                        file: path.relative(this.projectRoot, match[1]),
                        line: parseInt(match[2], 10),
                        content: match[3].trim()
                    });
                }
            }

            return { success: true, matches };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }

    /**
     * List files in directory
     */
    listFiles(dirPath: string = '.', pattern?: string): { success: boolean; files?: string[]; error?: string } {
        try {
            const resolved = this.resolvePath(dirPath);

            if (!fs.existsSync(resolved)) {
                return { success: false, error: `Directory not found: ${dirPath}` };
            }

            const files: string[] = [];
            const walk = (dir: string) => {
                const entries = fs.readdirSync(dir, { withFileTypes: true });
                for (const entry of entries) {
                    if (entry.name.startsWith('.')) continue;
                    const fullPath = path.join(dir, entry.name);
                    if (entry.isDirectory()) {
                        if (!['node_modules', 'build', '.dart_tool', '.git'].includes(entry.name)) {
                            walk(fullPath);
                        }
                    } else {
                        const relativePath = path.relative(this.projectRoot, fullPath);
                        if (!pattern || relativePath.endsWith(pattern) || entry.name.includes(pattern)) {
                            files.push(relativePath);
                        }
                    }
                }
            };

            walk(resolved);
            return { success: true, files };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }
}

// Code analysis tools
export class CodeAnalysis {
    private projectRoot: string;

    constructor(projectRoot?: string) {
        this.projectRoot = projectRoot || process.cwd();
    }

    setProjectRoot(root: string) {
        this.projectRoot = root;
    }

    /**
     * Run dart analyze
     */
    analyze(): { success: boolean; issues?: Array<{ severity: string; file: string; line: number; message: string }>; error?: string } {
        try {
            const result = spawnSync('dart', ['analyze', '--format=machine'], {
                cwd: this.projectRoot,
                encoding: 'utf-8',
                timeout: 120000,
                maxBuffer: 10 * 1024 * 1024
            });

            const issues: Array<{ severity: string; file: string; line: number; message: string }> = [];
            const output = result.stdout || result.stderr || '';

            // Parse machine format: SEVERITY|TYPE|FILE|LINE|COLUMN|MESSAGE
            const lines = output.split('\n').filter(Boolean);
            for (const line of lines) {
                const parts = line.split('|');
                if (parts.length >= 6) {
                    issues.push({
                        severity: parts[0],
                        file: path.relative(this.projectRoot, parts[2]),
                        line: parseInt(parts[3], 10),
                        message: parts.slice(5).join('|')
                    });
                }
            }

            return { success: true, issues };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }

    /**
     * Run dart fix
     */
    applyFixes(dryRun: boolean = false): { success: boolean; output?: string; error?: string } {
        try {
            const args = ['fix', dryRun ? '--dry-run' : '--apply'];
            const result = spawnSync('dart', args, {
                cwd: this.projectRoot,
                encoding: 'utf-8',
                timeout: 120000
            });

            if (result.error) {
                return { success: false, error: result.error.message };
            }

            return { success: true, output: result.stdout || result.stderr };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }

    /**
     * Run dart format
     */
    formatCode(filePath?: string): { success: boolean; output?: string; error?: string } {
        try {
            const target = filePath || '.';
            const result = spawnSync('dart', ['format', target], {
                cwd: this.projectRoot,
                encoding: 'utf-8',
                timeout: 60000
            });

            if (result.error) {
                return { success: false, error: result.error.message };
            }

            return { success: true, output: result.stdout };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }
}

// Test execution
export class TestRunner {
    private projectRoot: string;

    constructor(projectRoot?: string) {
        this.projectRoot = projectRoot || process.cwd();
    }

    setProjectRoot(root: string) {
        this.projectRoot = root;
    }

    /**
     * Run flutter tests
     */
    runTests(testPath?: string, reporter: string = 'compact'): { success: boolean; output?: string; passed?: number; failed?: number; error?: string } {
        try {
            const args = ['test'];
            if (reporter) {
                args.push('--reporter', reporter);
            }
            if (testPath) {
                args.push(testPath);
            }

            const result = spawnSync('flutter', args, {
                cwd: this.projectRoot,
                encoding: 'utf-8',
                timeout: 300000, // 5 minutes
                maxBuffer: 50 * 1024 * 1024
            });

            if (result.error) {
                return { success: false, error: result.error.message };
            }

            const output = result.stdout || '';

            // Parse test results
            const passMatch = output.match(/(\d+) tests? passed/);
            const failMatch = output.match(/(\d+) tests? failed/);

            const passed = passMatch ? parseInt(passMatch[1], 10) : 0;
            const failed = failMatch ? parseInt(failMatch[1], 10) : 0;

            return {
                success: result.status === 0,
                output,
                passed,
                failed
            };
        } catch (e: any) {
            return { success: false, error: e.message };
        }
    }

    /**
     * Run a single test file
     */
    runTestFile(testFile: string): { success: boolean; output?: string; error?: string } {
        return this.runTests(testFile, 'expanded');
    }
}

// Export singleton instances
export const vmService = new VmServiceClient();
export const fileOps = new FileOperations();
export const codeAnalysis = new CodeAnalysis();
export const testRunner = new TestRunner();

// Helper to set project root for all tools
export function setProjectRoot(root: string) {
    fileOps.setProjectRoot(root);
    codeAnalysis.setProjectRoot(root);
    testRunner.setProjectRoot(root);
}
