from tkinter import *
from PIL import Image, ImageTk
from tkinter import messagebox
from tkinter import ttk
import frontend.register
import backend.dbconnection


class Dashboard:
    def __init__(self, root):
        self.root = root
        self.root.title('Update')
        self.root.geometry('900x600')

        self.db = backend.dbconnection.DBConnect()

        lb = Label(self.root, text='Update', font=('arial', 20, 'bold'))
        lb.pack(fill=X)

        main_frame = Frame(self.root, bd=10, bg='silver')
        main_frame.place(x=0, y=180, width=400, height=350)

        Detail_Frame = Frame(self.root, bd=4, relief=RIDGE, bg="powderblue")
        Detail_Frame.place(x=400, y=180, width=500, height=350)

        lbl_uname = Label(main_frame, text='User Name', font=('arial', 15, 'bold'), \
                          bg='silver')
        lbl_uname.grid(row=0, column=0, padx=8, pady=10)

        self.ent_uname = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_uname.grid(row=0, column=1, padx=8, pady=10)

        lbl_password = Label(main_frame, text='Password', font=('arial', 15, 'bold'), \
                             bg='silver')
        lbl_password.grid(row=1, column=0, padx=8, pady=10)

        self.ent_password = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_password.grid(row=1, column=1, padx=8, pady=10)

        lbl_add = Label(main_frame, text='Address', font=('arial', 15, 'bold'), \
                        bg='silver')
        lbl_add.grid(row=2, column=0, padx=8, pady=10)

        self.ent_add = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_add.grid(row=2, column=1, padx=8, pady=10)

        lbl_cmb = Label(main_frame, text='Gender', font=('arial', 15, 'bold'), \
                        background='silver')
        lbl_cmb.grid(row=3, column=0)

        self.cmb_gender = ttk.Combobox(main_frame, font=('arial', 15, 'bold'))
        self.cmb_gender['values'] = ('Male', 'Female', 'Others')
        self.cmb_gender.grid(row=3, column=1)

        lbl_phone = Label(main_frame, text='phone no:', font=('arial', 15, 'bold'), \
                          bg='silver')
        lbl_phone.grid(row=4, column=0, padx=8, pady=10)

        self.ent_phone = Entry(main_frame, font=('arial', 15, 'bold'))
        self.ent_phone.grid(row=4, column=1, padx=8, pady=10)

        btn_update = Button(self.root, text='Update', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE,
                              padx=5)
        btn_update.place(x=120, y=450)

        btn_reset = Button(self.root, text='Reset', font=('arial', 15, 'bold'), width=8, bd=5, relief=GROOVE, command=self.reset_click(), padx=5)
        btn_reset.place(x=250, y=450)

    def reset_click(self):
        self.ent_uname.delete(0, END)
        self.ent_uname.insert(0, "")
        self.ent_password.insert(0, '')
        self.ent_password.delete(0, END)
        self.ent_add.delete(0, END)
        self.ent_add.insert(0, '')

    def deletedata(self):
        name = self.ent_uname.get()
        if (name == ""):
            messagebox.showinfo("Delete Status", "ID os compolsary for delete")
        else:
            query = "delete from user_tbl where name=%s"
            value = (name,)
            self.db.delete(query, value)
            messagebox.showinfo("Delete Status", "Deleted Succesfuly")


root = Tk()
Dashboard(root)
root.mainloop()
