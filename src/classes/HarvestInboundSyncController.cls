global class HarvestInboundSyncController {

    @future (callout=true)
    public static void sync() {
        Harvest h = new Harvest();
        Harvest__c settings = Harvest__c.getOrgDefaults();
        
        List<HarvestClient>  clients;
        List<HarvestContact> hContacts;
        List<HarvestProject> hProjects;
        
        
        //////////////////////////////////////////////////////////////////
        // Start with Callouts to Harvest
        
        if (settings.InboundLastRunDateTime__c != null) {
            clients = h.getClientsUpdatedSince(settings.InboundLastRunDateTime__c);
            hContacts = h.getContactsUpdatedSince(settings.InboundLastRunDateTime__c);
            hProjects = h.getProjectsUpdatedSince(settings.InboundLastRunDateTime__c);
        } else {
            clients   = h.getClients();
            hContacts = h.getContacts();
            hProjects = h.getProjects();
        }
        set<string> projectids = new set<string>();
        for (HarvestProject p : hProjects) {
            projectids.add(p.id);
        }

        List<HarvestUser> hUsers = h.getUsers();
        List<HarvestTask> hTasks = h.getTasks();
        /* RBW
        List<HarvestInvoice> hInvoices = h.getInvoices();
        if (hInvoices.size() == 50)
            hInvoices.addAll(h.getInvoicesByPage(2));
        if (hInvoices.size() == 100)
            hInvoices.addAll(h.getInvoicesByPage(3));
        if (hInvoices.size() == 150)
            hInvoices.addAll(h.getInvoicesByPage(4));
        */

        // GET TIME ENTRIES for these projects from Harvest (max 100 !)
        Set<HarvestTimeEntry>      hTimeEntries     = new Set<HarvestTimeEntry>();
        Set<HarvestTaskAssignment> hTaskAssignments = new Set<HarvestTaskAssignment>();
        Set<HarvestUserAssignment> hUserAssignments = new Set<HarvestUserAssignment>();
        for (String projectid : projectids) {
            hTimeEntries.addAll(h.getTimeEntriesForProject(projectid));
            hTaskAssignments.addAll(h.getTaskAssignments(projectid));
            hUserAssignments.addAll(h.getUserAssignments(projectid));
        }


        ////////////////////////////////////////////////////////////////
        // Callouts done to Harvest
        // Now, process data and upsert to Salesforce
        
        
        HarvestAsyncControl.inFutureContext = true;
        
        /*PROCESS CLIENTS*/      
        List<Account> accounts = new List<Account>();
        for (HarvestClient c : clients) {
            accounts.add(HarvestUtil.transformClient(c));
        }   
        upsert accounts Harvest_Id__c;
        
        /*PROCESS CONTACTS*/        
        set<string> clientIds = new set<string>();
        for (HarvestContact c: hContacts) {
            clientIds.add(c.clientId);
        }  
        Map<String, Id> accountMap = HarvestUtil.getHarvestAccountMap(clientIds);   

        List<Contact> contacts = new List<Contact>();
        for (HarvestContact c : hContacts) {
            contacts.add(HarvestUtil.transformContact(c, accountMap));
        }   
        upsert contacts Harvest_Id__c;  
                
        /*PROCESS PROJECTS*/
        clientIds.clear();
        for (HarvestProject p : hProjects) {
            clientIds.add(p.clientId);
        } 
        
        accountMap.clear(); 
        accountMap = HarvestUtil.getHarvestAccountMap(clientIds);   
        
        List<Harvest_Project__c> projects = new List<Harvest_Project__c>();
        for (HarvestProject p : hProjects) {
            projects.add(HarvestUtil.transformProject(p, accountMap));
        }
        upsert projects Harvest_Id__c;
        Map<String, Id> projectMap = HarvestUtil.getHarvestProjectMap(projectIds);   


        /*PROCESS USERS*/
        List<Harvest_User__c> users = new List<Harvest_User__c>();
        for (HarvestUser hu : hUsers) {
            users.add(HarvestUtil.transformUser(hu));
        }
        upsert users Harvest_Id__c;
        Map<String, Id> userMap = HarvestUtil.getHarvestUserMap();   
        /*
        for (HarvestTaskAssignment lhta : hTaskAssignments) {
            System.Debug('### Harvest task assignment = ' + lhta);
        }
        */

        /*PROCESS TASKS*/
        List<Harvest_Task__c> tasks = new List<Harvest_Task__c>();
        for (HarvestTask ht : hTasks) {
            tasks.add(HarvestUtil.transformTask(ht));
        }
        upsert tasks Harvest_Id__c;
        Map<String, Id> taskMap = HarvestUtil.getHarvestTaskMap();   
        for (HarvestTaskAssignment lhta : hTaskAssignments) {
            System.Debug('### Harvest task assignment = ' + lhta);
        }

        /*PROCESS INVOICES*/
        /* RBW
        clientIds.clear();
        clientIds = new Set<String>();
        for (HarvestInvoice hi : hInvoices) {
            clientIds.add(hi.clientId);
        } 
        
        Map<String, Id> clientMap = new Map<String, Id>();
        for (Account a : [Select Id, Harvest_Id__c from Account where Harvest_Id__c in :clientIds])
            clientMap.put(a.Harvest_Id__c, a.Id);
            
        List<Harvest_Invoice__c> invoices = new List<Harvest_Invoice__c>();
        for (HarvestInvoice hi : hInvoices) {
            invoices.add(HarvestUtil.transformInvoice(hi, clientMap));
        }  
        upsert invoices Harvest_Id__c;
        */

        // PROCESS TIME ENTRIES
        List<Harvest_Time_Entry__c> entries = new List<Harvest_Time_Entry__c >();
        for (HarvestTimeEntry hte : hTimeEntries) {
            entries.add(HarvestUtil.transformTimeEntry(hte, projectMap, taskMap));
        }
        upsert entries Harvest_Id__c;

        // PROCESS TASK ASSIGNMENTS
        List<Harvest_Task_Assignment__c> taskassigs = new List<Harvest_Task_Assignment__c>();
        for (HarvestTaskAssignment hta : hTaskAssignments) {
            taskassigs.add(HarvestUtil.transformTaskAssignment(hta, projectMap, taskMap));
        }
        /*
        for (HarvestTaskAssignment lhta : hTaskAssignments) {
            System.Debug('### Harvest task assignment = ' + lhta);
        }
        */
        for (Harvest_Task_Assignment__c lt : taskassigs) {
            if (lt.task__c == NULL) {
                System.Debug('### task assignment = ' + lt);
            }
        }
        upsert taskassigs Harvest_Id__c;

        // PROCESS USER ASSIGNMENTS
        List<Harvest_User_Assignment__c> userassigs = new List<Harvest_User_Assignment__c>();
        for (HarvestUserAssignment htua : hUserAssignments) {
            userassigs.add(HarvestUtil.transformUserAssignment(htua, projectMap, userMap));
        }
        upsert userassigs Harvest_Id__c;



        settings.InboundLastRunDateTime__c = DateTime.now();
        upsert settings;
    }

}